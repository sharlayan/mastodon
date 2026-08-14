# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation do
  describe 'ID generation' do
    it 'uses a timestamp-based ID for new conversations' do
      conversation = Fabricate(:conversation)

      expect(described_class.columns_hash['id'].default_function).to eq("timestamp_id('conversations'::text)")
      expect(conversation.id).to be > Mastodon::Snowflake.id_at(1.day.ago, with_random: false)
    end
  end

  describe '#local?' do
    it 'returns true when URI is nil' do
      expect(Fabricate(:conversation).local?).to be true
    end

    it 'returns false when URI is not nil' do
      expect(Fabricate(:conversation, uri: 'abc').local?).to be false
    end
  end
end
