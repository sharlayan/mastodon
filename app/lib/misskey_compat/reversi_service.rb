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
    MisskeyReversiGame.transaction do
      game = MisskeyReversiGame.lock.find_by(id: game_id)
      yield game if game
    end
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

  def publish_user(account_id, type, body)
    publish("reversi:#{account_id}", type, body)
  end

  def publish_game(game_id, type, body)
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
