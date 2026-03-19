# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::EmojiReactionSerializer do
  subject { serialized_record_json(reaction, described_class, adapter: ActivityPub::Adapter) }

  let(:tag_manager) { ActivityPub::TagManager.instance }
  let(:account)     { Fabricate(:account) }
  let(:status)      { Fabricate(:status) }

  context 'with a unicode emoji' do
    let(:reaction) { Fabricate(:status_reaction, account: account, status: status, name: '👍', custom_emoji: nil) }

    it 'serializes to the expected json' do
      expect(subject).to include({
        'id' => "#{tag_manager.uri_for(account)}#emoji_reactions/#{reaction.id}",
        'type' => 'Like',
        'actor' => tag_manager.uri_for(account),
        'object' => tag_manager.uri_for(status),
        'content' => '👍',
        '_misskey_reaction' => '👍',
      })
    end

    it 'does not include tag' do
      expect(subject).to_not have_key('tag')
    end
  end

  context 'with a custom emoji' do
    let(:custom_emoji) { Fabricate(:custom_emoji) }
    let(:reaction) { Fabricate(:status_reaction, account: account, status: status, name: custom_emoji.shortcode, custom_emoji: custom_emoji) }

    it 'serializes to the expected json' do
      expect(subject).to include({
        'id' => "#{tag_manager.uri_for(account)}#emoji_reactions/#{reaction.id}",
        'type' => 'Like',
        'actor' => tag_manager.uri_for(account),
        'object' => tag_manager.uri_for(status),
        'content' => ":#{custom_emoji.shortcode}:",
        '_misskey_reaction' => ":#{custom_emoji.shortcode}:",
      })
    end

    it 'includes tag array with emoji data' do
      expect(subject['tag']).to be_an(Array)
      expect(subject['tag'].first).to include({
        'type' => 'Emoji',
        'name' => ":#{custom_emoji.shortcode}:",
      })
    end
  end
end
