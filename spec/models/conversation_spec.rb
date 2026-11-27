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
    subject { Fabricate.build :conversation, uri: }

    context 'when uri is nil' do
      let(:uri) { nil }

      it { is_expected.to be_local }
    end

    context 'when uri is set' do
      let(:uri) { 'abc' }

      it { is_expected.to_not be_local }
    end
  end
end
