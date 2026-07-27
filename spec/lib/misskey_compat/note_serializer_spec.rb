# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::NoteSerializer do
  describe 'local mentions' do
    it 'adds the configured local port to an already-qualified mention' do
      mentioned_account = Fabricate(:account, username: 'bob')
      status = Fabricate(:status, text: '@bob@localhost hello')
      Fabricate(:mention, status: status, account: mentioned_account)
      allow(Rails.configuration.x).to receive(:local_domain).and_return('localhost:3000')

      serialized = described_class.serialize(status)

      expect(serialized[:text]).to eq('@bob@localhost:3000 hello')
    end

    it 'does not duplicate the port when the mention already includes it' do
      mentioned_account = Fabricate(:account, username: 'bob')
      status = Fabricate(:status, text: '@bob@localhost:3000 hello')
      Fabricate(:mention, status: status, account: mentioned_account)
      allow(Rails.configuration.x).to receive(:local_domain).and_return('localhost:3000')

      serialized = described_class.serialize(status)

      expect(serialized[:text]).to eq('@bob@localhost:3000 hello')
    end
  end

  describe 'reactions' do
    let(:status) { Fabricate(:status) }

    it 'exposes unicode reactions with their raw name' do
      Fabricate(:status_reaction, status: status, name: '👍', custom_emoji: nil)

      serialized = described_class.serialize(status)

      expect(serialized[:reactions]).to eq({ '👍' => 1 })
      expect(serialized[:reactionEmojis]).to eq({})
    end

    it 'exposes local custom emoji reactions in the note emoji map' do
      custom_emoji = Fabricate(:custom_emoji, shortcode: 'thonk', domain: nil)
      Fabricate(:status_reaction, status: status, name: 'thonk', custom_emoji: custom_emoji)

      serialized = described_class.serialize(status)

      expect(serialized[:reactions]).to eq({ ':thonk@.:' => 1 })
      expect(serialized[:emojis]['thonk@.']).to be_present
      expect(serialized[:emojis]['thonk']).to eq serialized[:emojis]['thonk@.']
    end

    it 'exposes remote custom emoji reactions in both emoji maps' do
      custom_emoji = Fabricate(:custom_emoji, shortcode: 'blobcat', domain: 'other.com')
      Fabricate(:status_reaction, status: status, name: 'blobcat', custom_emoji: custom_emoji)

      serialized = described_class.serialize(status)

      expect(serialized[:reactions]).to eq({ ':blobcat@other.com:' => 1 })
      expect(serialized[:reactionEmojis]['blobcat@other.com']).to be_present
      expect(serialized[:emojis]['blobcat@other.com']).to eq serialized[:reactionEmojis]['blobcat@other.com']
    end

    it 'keeps text emoji entries when a reaction shares the shortcode' do
      custom_emoji = Fabricate(:custom_emoji, shortcode: 'thonk', domain: nil)
      status = Fabricate(:status, text: 'hello :thonk:')
      Fabricate(:status_reaction, status: status, name: 'thonk', custom_emoji: custom_emoji)

      serialized = described_class.serialize(status)

      expect(serialized[:emojis]['thonk']).to be_present
    end
  end
end
