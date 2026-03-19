# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::UndoEmojiReactionSerializer do
  subject { serialized_record_json(reaction, described_class, adapter: ActivityPub::Adapter) }

  let(:tag_manager) { ActivityPub::TagManager.instance }
  let(:account)     { Fabricate(:account) }
  let(:status)      { Fabricate(:status) }

  context 'with a unicode emoji' do
    let(:reaction) { Fabricate(:status_reaction, account: account, status: status, name: '👍', custom_emoji: nil) }

    it 'serializes to the expected json' do
      expect(subject).to include({
        'id' => "#{tag_manager.uri_for(account)}#emoji_reactions/#{reaction.id}/undo",
        'type' => 'Undo',
        'actor' => tag_manager.uri_for(account),
      })
    end

    it 'includes nested reaction object' do
      expect(subject['object']).to include({
        'type' => 'Like',
        'actor' => tag_manager.uri_for(account),
        'object' => tag_manager.uri_for(status),
        'content' => '👍',
      })
    end
  end

  context 'with a custom emoji' do
    let(:custom_emoji) { Fabricate(:custom_emoji) }
    let(:reaction) { Fabricate(:status_reaction, account: account, status: status, name: custom_emoji.shortcode, custom_emoji: custom_emoji) }

    it 'serializes to the expected json' do
      expect(subject).to include({
        'type' => 'Undo',
        'actor' => tag_manager.uri_for(account),
      })
    end

    it 'includes nested reaction with custom emoji content' do
      expect(subject['object']).to include({
        'type' => 'Like',
        'content' => ":#{custom_emoji.shortcode}:",
      })
    end
  end
end
