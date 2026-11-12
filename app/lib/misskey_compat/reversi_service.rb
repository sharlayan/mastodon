# frozen_string_literal: true

class MisskeyCompat::ReversiService
  include Redisable

  INVITATION_TIMEOUT = 20.seconds
  INVITATION_KEY_TTL = 120
  MATCH_ANY_KEY = 'misskey:reversi:match_any'
  MATCH_ANY_KEY_TTL = 15
  NO_IRREGULAR_RULES_SUFFIX = ':noIrregularRules'
  PENDING_MATCH_WINDOW = 3.minutes
  OUTDATED_GAME_AGE = 10.minutes
  START_DELAY = 3.seconds
  BOOLEAN_SETTINGS = { 'isLlotheo' => :llotheo, 'canPutEverywhere' => :can_put_everywhere, 'loopedBoard' => :looped_board }.freeze
  UPDATE_KEYS = (%w(map bw timeLimitForEachTurn) + BOOLEAN_SETTINGS.keys).freeze

  def match_specific_user(account, target, multiple: false)
    clean_outdated_games

    unless multiple
      game = pending_games.where(account1_id: account.id, account2_id: target.id).or(pending_games.where(account1_id: target.id, account2_id: account.id)).first
      return game if game
    end

    return matched(target.id, account.id, no_irregular_rules: false) if invitation_ids(account.id).include?(target.id.to_s) && claim_invitation(account.id, target.id)
    return if target.blocking?(account) || account.blocking?(target)

    redis.multi do |transaction|
      transaction.zadd(invitation_key(target.id), now_ms, account.id.to_s)
      transaction.expire(invitation_key(target.id), INVITATION_KEY_TTL, nx: true)
    end

    publish_user(target.id, 'invited', { user: MisskeyCompat::UserSerializer.serialize(account) })
    nil
  end

  def match_any_user(account, no_irregular_rules: false, multiple: false)
    clean_outdated_games

    unless multiple
      game = pending_games.involving(account).first
      return game if game
    end

    invitation_ids(account.id).shuffle.each do |inviter_id|
      return matched(inviter_id.to_i, account.id, no_irregular_rules: false) if claim_invitation(account.id, inviter_id)
    end

    redis.zrevrange(MATCH_ANY_KEY, 0, 2).each do |entry|
      waiting_id, option = entry.split(':', 2)
      next if waiting_id == account.id.to_s
      next unless redis.zrem(MATCH_ANY_KEY, entry)

      redis.zrem(MATCH_ANY_KEY, [waiting_id, "#{waiting_id}#{NO_IRREGULAR_RULES_SUFFIX}"])
      cancel_match_any(account)
      return matched(waiting_id.to_i, account.id, no_irregular_rules: no_irregular_rules || option == 'noIrregularRules')
    end

    redis.multi do |transaction|
      transaction.zadd(MATCH_ANY_KEY, now_ms, no_irregular_rules ? "#{account.id}#{NO_IRREGULAR_RULES_SUFFIX}" : account.id.to_s)
      transaction.expire(MATCH_ANY_KEY, MATCH_ANY_KEY_TTL, nx: true)
    end
    nil
  end

  def cancel_match_specific_user(account, target_id)
    redis.zrem(invitation_key(target_id), account.id.to_s)
  end

  def cancel_match_any(account)
    redis.zrem(MATCH_ANY_KEY, [account.id.to_s, "#{account.id}#{NO_IRREGULAR_RULES_SUFFIX}"])
  end

  def invitation_ids(account_id)
    redis.zrangebyscore(invitation_key(account_id), now_ms - INVITATION_TIMEOUT.in_milliseconds, '+inf')
  end

  def surrender(game, account)
    with_game(game.id) do |locked|
      next if locked.ended? || !locked.participant?(account)

      end_game(locked, locked.other_account_id(account.id), :surrender)
    end
  end

  def ready(game_id, account, ready)
    with_game(game_id) do |game|
      slot = game.slot_of(account)
      next if game.started? || slot.nil?

      game.update!("account#{slot}_ready" => ready)
      publish_game(game.id, 'changeReadyStates', { user1: game.account1_ready, user2: game.account2_ready })
      MisskeyCompatReversiActionWorker.perform_in(START_DELAY, nil, game.id.to_s, 'start') if game.account1_ready && game.account2_ready
    end
  end

  def start_game(game_id)
    with_game(game_id) do |game|
      next if game.started? || game.ended? || !(game.account1_ready && game.account2_ready)

      black = game.bw == 'random' ? [1, 2].sample : game.bw.to_i
      engine = MisskeyCompat::ReversiEngine.new(game.map, llotheo: game.llotheo, can_put_everywhere: game.can_put_everywhere, looped_board: game.looped_board)
      game.update!(started_at: Time.current, black: black, crc32: engine.crc32.to_s)

      if engine.ended?
        end_game(game, engine.winner.nil? ? nil : game.account_id_for_color(engine.winner))
      else
        start_turn_timer(game, engine.turn)
        publish_game(game.id, 'started', { game: MisskeyCompat::ReversiGameSerializer.detail(game) })
      end
    end
  end

  def update_settings(game_id, account, key, value)
    return unless valid_setting?(key, value)

    with_game(game_id) do |game|
      slot = game.slot_of(account)
      next if game.started? || slot.nil? || game.ready_of?(slot)

      game.update!(setting_attribute(key) => value)
      publish_game(game.id, 'updateSettings', { userId: MisskeyCompat::MiId.encode(account.id), key: key, value: value })
    end
  end

  def put_stone(game_id, account, pos, operation_id = nil)
    with_game(game_id) do |game|
      next if !game.started? || game.ended? || !game.participant?(account)

      color = game.color_of(account)
      engine = game.engine
      next if engine.turn != color || !engine.can_put?(color, pos)

      engine.put_stone(pos)
      log = MisskeyCompat::ReversiEngine::Log.new(time: now_ms, player: color, operation: 'put', pos: pos)
      logs = MisskeyCompat::ReversiEngine.serialize_logs(MisskeyCompat::ReversiEngine.deserialize_logs(game.logs) + [log])
      game.update!(logs: logs, crc32: engine.crc32.to_s)
      publish_game(game.id, 'log', log.to_h.merge(id: operation_id))

      if engine.ended?
        end_game(game, engine.winner.nil? ? nil : game.account_id_for_color(engine.winner))
      else
        start_turn_timer(game, engine.turn)
      end
    end
  end

  def check_timeout(game_id)
    with_game(game_id) do |game|
      next if !game.started? || game.ended?

      turn = game.engine.turn
      next if turn.nil? || redis.exists?(turn_timer_key(game.id, turn))

      end_game(game, game.account_id_for_color(!turn), :timeout)
    end
  end

  def cancel_game(game_id, account)
    with_game(game_id) do |game|
      next if game.started? || !game.participant?(account)

      game.destroy!
      publish_game(game.id, 'canceled', { userId: MisskeyCompat::MiId.encode(account.id) })
    end
  end

  def desynced_game(game, crc32)
    crc32.to_s == game.crc32.to_s ? nil : game
  end

  def clean_outdated_games
    MisskeyReversiGame.not_started.where(created_at: ...OUTDATED_GAME_AGE.ago).delete_all
  end

  private

  def pending_games
    MisskeyReversiGame.not_started.where(created_at: PENDING_MATCH_WINDOW.ago..).order(id: :desc)
  end

  def claim_invitation(account_id, inviter_id)
    redis.zrem(invitation_key(account_id), inviter_id.to_s)
  end

  def matched(parent_id, child_id, no_irregular_rules:)
    game = MisskeyReversiGame.create!(account1_id: parent_id, account2_id: child_id, map: MisskeyCompat::ReversiEngine::DEFAULT_MAP, bw: 'random', no_irregular_rules: no_irregular_rules)
    publish_user(parent_id, 'matched', { game: MisskeyCompat::ReversiGameSerializer.detail(game) })
    game
  end

  def with_game(game_id)
    @deferred_events = []
    MisskeyReversiGame.transaction do
      game = MisskeyReversiGame.lock.find_by(id: game_id)
      yield game if game
    end
    @deferred_events.each { |event| publish(*event) }
  ensure
    @deferred_events = nil
  end

  def end_game(game, winner_id, reason = nil)
    loser_id = winner_id && game.other_account_id(winner_id)
    game.update!(
      ended_at: Time.current,
      winner_account_id: winner_id,
      surrendered_account_id: reason == :surrender ? loser_id : nil,
      timeout_account_id: reason == :timeout ? loser_id : nil
    )
    publish_game(game.id, 'ended', { winnerId: MisskeyCompat::MiId.encode(winner_id), game: MisskeyCompat::ReversiGameSerializer.detail(game) })
  end

  def valid_setting?(key, value)
    case key
    when 'map' then MisskeyReversiGame.valid_map?(value)
    when 'bw' then MisskeyReversiGame::BW_VALUES.include?(value)
    when 'timeLimitForEachTurn' then value.is_a?(Integer) && value.between?(0, MisskeyReversiGame::MAX_TIME_LIMIT)
    when *BOOLEAN_SETTINGS.keys then [true, false].include?(value)
    else false
    end
  end

  def setting_attribute(key)
    BOOLEAN_SETTINGS.fetch(key) { key == 'timeLimitForEachTurn' ? :time_limit_for_each_turn : key.to_sym }
  end

  def start_turn_timer(game, turn)
    key = turn_timer_key(game.id, turn)
    game.time_limit_for_each_turn.positive? ? redis.setex(key, game.time_limit_for_each_turn, '') : redis.del(key)
  end

  def turn_timer_key(game_id, turn)
    "misskey:reversi:turn_timer:#{game_id}:#{turn ? 1 : 0}"
  end

  def publish_user(account_id, type, body)
    publish("reversi:#{account_id}", type, body)
  end

  def publish_game(game_id, type, body)
    return @deferred_events << ["reversiGame:#{game_id}", type, body] if @deferred_events

    publish("reversiGame:#{game_id}", type, body)
  end

  def publish(channel, type, body)
    return unless redis.exists?("subscribed:misskey:#{channel}")

    redis.publish("misskey:#{channel}", JSON.generate({ event: 'reversi', payload: { type: type, body: body } }))
  rescue Redis::BaseError => e
    Rails.logger.warn("[misskey_compat] reversi broadcast failed for #{channel}: #{e.class} #{e.message}")
  end

  def invitation_key(account_id)
    "misskey:reversi:match_specific:#{account_id}"
  end

  def now_ms
    (Time.now.to_f * 1000).to_i
  end
end
