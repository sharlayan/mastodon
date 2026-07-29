# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmojiMuteCache do
  let(:account) { Fabricate(:account) }

  describe '.write' do
    it 'stores normalized rules' do
      account.custom_emoji_mutes.create!(prefix: ' Blob ', domain: 'Example.com')

      expect(described_class.read(account.id)).to eq([{ 'prefix' => 'blob', 'domain' => 'example.com' }])
    end

    it 'caps the stored rules at MAX_RULES' do
      stub_const('CustomEmojiMuteCache::MAX_RULES', 2)
      3.times { |index| account.custom_emoji_mutes.create!(prefix: "mute#{index}") }

      expect(described_class.read(account.id).size).to eq(2)
    end

    it 'removes the key instead of storing an empty rule set' do
      mute = account.custom_emoji_mutes.create!(prefix: 'blob')
      mute.destroy!

      expect(RedisConnection.with { |redis| redis.exists?(described_class.key(account.id)) }).to be false
    end
  end

  describe '.read' do
    it 'caps rules read from a legacy oversized cache entry' do
      stub_const('CustomEmojiMuteCache::MAX_RULES', 2)
      rules = Array.new(5) { |index| { 'prefix' => "mute#{index}", 'domain' => '' } }
      RedisConnection.with { |redis| redis.set(described_class.key(account.id), JSON.generate(rules)) }

      expect(described_class.read(account.id).size).to eq(2)
    end

    it 'returns an empty list for a non-array payload' do
      RedisConnection.with { |redis| redis.set(described_class.key(account.id), JSON.generate({ 'prefix' => 'blob' })) }

      expect(described_class.read(account.id)).to eq([])
    end
  end
end
