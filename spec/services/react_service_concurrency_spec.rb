# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReactService, use_transactional_tests: false do
  let(:account) { Fabricate(:account) }
  let(:author) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: author) }
  let(:first_prepared) { Queue.new }
  let(:release_first) { Queue.new }
  let(:second_connection_ids) { Queue.new }
  let(:second_finished) { Queue.new }
  let(:reaction_threads) { [] }
  let(:pause_first_reaction) do
    prepared = first_prepared
    release = release_first
    proc do |reaction|
      if reaction.name == '👍'
        prepared << true
        release.pop
      end
    end
  end

  before do
    account
    status
    StatusReaction.set_callback(:create, :before, pause_first_reaction)
  end

  after do
    release_first << true
    reaction_threads.each(&:join)
    StatusReaction.skip_callback(:create, :before, pause_first_reaction)
    status.destroy!
    account.destroy!
    author.destroy!
  end

  it 'keeps a single reaction when two different emojis are submitted concurrently' do
    first = start_reaction('👍')
    Timeout.timeout(5) { first_prepared.pop }
    second = start_reaction('🎉', track_connection: true)
    pid = Timeout.timeout(5) { second_connection_ids.pop }
    wait_for_second_write(pid)
    release_first << true

    [first, second].each(&:value)

    expect(StatusReaction.where(account: account, status: status).pluck(:name)).to eq(['🎉'])
    expect(status.reload.reactions_count).to eq(1)
  end

  it 'does not lock the account row while a reaction is being created' do
    first = start_reaction('👍')
    Timeout.timeout(5) { first_prepared.pop }

    Account.transaction do
      Account.connection.execute("SET LOCAL lock_timeout = '2s'")
      Account.where(id: account.id).update_all(note: 'updated')
    end
    release_first << true
    first.value

    expect(account.reload.note).to eq('updated')
    expect(StatusReaction.where(account: account, status: status).pluck(:name)).to eq(['👍'])
  end

  def start_reaction(emoji, track_connection: false)
    reaction_threads << Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        second_connection_ids << connection.select_value('SELECT pg_backend_pid()') if track_connection
        described_class.new.call(Account.find(account.id), Status.find(status.id), emoji).tap do
          second_finished << true if track_connection
        end
      end
    end
    reaction_threads.last
  end

  def wait_for_second_write(pid)
    Timeout.timeout(5) do
      loop do
        break unless second_finished.empty?
        break if ApplicationRecord.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{pid.to_i}") == 'Lock'

        sleep 0.01
      end
    end
  end
end
