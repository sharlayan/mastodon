# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::ReversiService do
  subject(:service) { described_class.new }

  let(:host)  { Fabricate(:account) }
  let(:guest) { Fabricate(:account) }
  let(:game)  { MisskeyReversiGame.create!(account1: host, account2: guest, map: MisskeyCompat::ReversiEngine::DEFAULT_MAP) }
  let(:published) { [] }

  before do
    allow(redis).to receive(:publish).and_wrap_original do |original, channel, message|
      published << [channel, JSON.parse(message)]
      original.call(channel, message)
    end
  end

  def subscribe(channel)
    redis.set("subscribed:misskey:#{channel}", '1')
  end

  def events(channel)
    published.filter_map { |name, message| [message.dig('payload', 'type'), message.dig('payload', 'body')] if name == "misskey:#{channel}" && message['event'] == 'reversi' }
  end

  def started_game(**attributes)
    game.update!({ account1_ready: true, account2_ready: true, bw: '1' }.merge(attributes))
    service.start_game(game.id)
    game.reload
  end

  it 'publishes invitations and matches only to subscribed lobbies' do
    subscribe("reversi:#{guest.id}")
    subscribe("reversi:#{host.id}")

    service.match_specific_user(host, guest)
    expect(events("reversi:#{guest.id}")).to contain_exactly(['invited', include('user' => include('id' => MisskeyCompat::MiId.encode(host.id)))])

    created = service.match_specific_user(guest, host)
    expect(events("reversi:#{host.id}")).to contain_exactly(['matched', include('game' => include('id' => MisskeyCompat::MiId.encode(created.id), 'map' => MisskeyCompat::ReversiEngine::DEFAULT_MAP))])

    service.match_specific_user(guest, Fabricate(:account))
    expect(published.size).to eq(2)
  end

  it 'records ready states, starts three seconds after both are ready and assigns colors' do
    subscribe("reversiGame:#{game.id}")

    service.ready(game.id, host, true)
    expect(MisskeyCompatReversiActionWorker.jobs).to be_empty
    service.ready(game.id, guest, true)
    service.ready(game.id, Fabricate(:account), true)

    expect(events("reversiGame:#{game.id}")).to eq([['changeReadyStates', { 'user1' => true, 'user2' => false }], ['changeReadyStates', { 'user1' => true, 'user2' => true }]])
    expect(MisskeyCompatReversiActionWorker.jobs.sole).to include('args' => [nil, game.id.to_s, 'start'], 'at' => be_within(1).of(3.seconds.from_now.to_f))

    service.start_game(game.id)
    game.reload
    expect(game).to have_attributes(started?: true, crc32: '1090129541')
    expect(game.black).to be_in([1, 2])
    expect(events("reversiGame:#{game.id}").last).to match(['started', include('game' => include('isStarted' => true, 'black' => game.black))])
    expect(redis.ttl("misskey:reversi:turn_timer:#{game.id}:1")).to be_between(1, 90)

    service.ready(game.id, host, false)
    expect(game.reload.account1_ready).to be(true)
  end

  it 'updates settings until the player is ready and ignores invalid values' do
    subscribe("reversiGame:#{game.id}")

    service.update_settings(game.id, host, 'map', %w(---- -wb- -bw- ----))
    service.update_settings(game.id, guest, 'isLlotheo', true)
    service.update_settings(game.id, guest, 'timeLimitForEachTurn', 30)
    service.update_settings(game.id, guest, 'bw', '2')
    service.update_settings(game.id, guest, 'bw', 'black')
    service.update_settings(game.id, guest, 'map', ['-' * 40])
    service.update_settings(game.id, guest, 'noIrregularRules', true)
    service.ready(game.id, host, true)
    service.update_settings(game.id, host, 'loopedBoard', true)

    expect(game.reload).to have_attributes(map: %w(---- -wb- -bw- ----), llotheo: true, time_limit_for_each_turn: 30, bw: '2', looped_board: false, no_irregular_rules: false)
    expect(events("reversiGame:#{game.id}").first).to eq(['updateSettings', { 'userId' => MisskeyCompat::MiId.encode(host.id), 'key' => 'map', 'value' => %w(---- -wb- -bw- ----) }])
  end

  it 'applies legal moves in turn order, logs them and ends the game with the winner' do
    started_game(map: %w(-wb), time_limit_for_each_turn: 0)
    subscribe("reversiGame:#{game.id}")

    service.put_stone(game.id, guest, 0, 'wrong-turn')
    service.put_stone(game.id, host, 2, 'occupied')
    service.put_stone(game.id, host, 0, 'op')
    game.reload

    expect(game.logs).to match([[be_a(Integer), 1, 0, 0]])
    expect(game).to have_attributes(ended?: true, winner_account_id: host.id, timeout_account_id: nil, crc32: game.engine.crc32.to_s)
    expect(events("reversiGame:#{game.id}").map(&:first)).to eq(%w(log ended))
    expect(events("reversiGame:#{game.id}").first.last).to include('player' => true, 'operation' => 'put', 'pos' => 0, 'id' => 'op')
    expect(events("reversiGame:#{game.id}").last.last).to include('winnerId' => MisskeyCompat::MiId.encode(host.id))
  end

  it 'ends games on expired turn timers and lets participants cancel unstarted games' do
    service.check_timeout(game.id)
    expect(game.reload.ended?).to be(false)

    started_game
    service.check_timeout(game.id)
    expect(game.reload.ended?).to be(false)

    redis.del("misskey:reversi:turn_timer:#{game.id}:1")
    service.check_timeout(game.id)
    expect(game.reload).to have_attributes(ended?: true, winner_account_id: guest.id, timeout_account_id: host.id)

    pending_game = MisskeyReversiGame.create!(account1: host, account2: guest, map: %w(--))
    subscribe("reversiGame:#{pending_game.id}")
    service.cancel_game(pending_game.id, Fabricate(:account))
    expect(MisskeyReversiGame.exists?(pending_game.id)).to be(true)
    service.cancel_game(pending_game.id, guest)
    expect(MisskeyReversiGame.exists?(pending_game.id)).to be(false)
    expect(events("reversiGame:#{pending_game.id}")).to eq([['canceled', { 'userId' => MisskeyCompat::MiId.encode(guest.id) }]])
  end

  it 'decides games that cannot be played from the initial board immediately' do
    started_game(map: %w(b--), bw: '2')

    expect(game).to have_attributes(started?: true, ended?: true, black: 2, winner_account_id: guest.id)
  end
end
