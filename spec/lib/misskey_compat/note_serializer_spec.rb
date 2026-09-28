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
      expect(serialized[:reactionCount]).to eq(1)
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

  it 'includes required reaction fields on a pure renote' do
    original = Fabricate(:status)
    renote = Fabricate(:status, reblog: original, text: '', reaction_acceptance: 'likeOnly')

    serialized = described_class.serialize(renote)

    expect(serialized).to include(reactionAcceptance: 'likeOnly', reactions: {}, reactionCount: 0)
  end

  it 'counts accepted quotes as renotes without exposing a pending quote relationship' do
    root = Fabricate(:status)
    Fabricate(:status, reblog: root)
    accepted = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'accepted'), state: :accepted)
    pending = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'pending'), state: :pending)

    expect(described_class.serialize(root)[:renoteCount]).to eq(2)
    expect(described_class.serialize(accepted.status)[:renoteId]).to eq(MisskeyCompat::MiId.encode(root.id))
    expect(described_class.serialize(pending.status)[:renoteId]).to be_nil
  end
end
