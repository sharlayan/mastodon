# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatFederation::ReactionState do
  let(:actor) { instance_double(Account, id: 123) }

  it 'atomically limits concurrent admissions across different messages' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 2)
    states = Array.new(10) { |index| described_class.new(actor, instance_double(ChatMessage, id: index), '👍') }
    ready = Queue.new
    start = Queue.new
    threads = states.map.with_index do |state, index|
      Thread.new do
        ready << true
        start.pop
        state.add("https://remote.test/chat-reactions/#{index}")
      ensure
        RedisConnection.pool.checkin if Thread.current[:redis]
        Thread.current[:redis] = nil
      end
    end
    threads.size.times { ready.pop }
    threads.size.times { start << true }

    expect(threads.map(&:value).count { |accepted| accepted }).to eq(2)
  ensure
    threads&.each(&:join)
  end

  it 'counts reuse of one ID on different messages against the aggregate limit' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 1)
    first = described_class.new(actor, instance_double(ChatMessage, id: 1), '👍')
    second = described_class.new(actor, instance_double(ChatMessage, id: 2), '👍')

    first.add('https://remote.test/chat-reactions/reused')

    expect(second.add('https://remote.test/chat-reactions/reused')).to be(false)
  end

  it 'expires aggregate admission state along with each reaction ID' do
    stub_const('Sharlayan::ChatFederation::ReactionState::MAX_ACTOR_ACTIVE_IDS', 1)
    first = described_class.new(actor, instance_double(ChatMessage, id: 1), '👍')
    second = described_class.new(actor, instance_double(ChatMessage, id: 2), '👍')

    first.add('https://remote.test/chat-reactions/first')
    travel 6.hours - 1.second
    expect(second.add('https://remote.test/chat-reactions/second')).to be(false)

    travel 2.seconds
    expect(second.add('https://remote.test/chat-reactions/second')).to be(true)
  end
end
