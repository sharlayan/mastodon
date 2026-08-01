# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Clip do
  describe 'ID generation' do
    it 'uses a timestamp-based ID' do
      clip = described_class.create!(account: Fabricate(:account), title: 'Clip')

      expect(Mastodon::Snowflake.to_time(clip.id)).to be_within(1.minute).of(Time.current)
    end
  end
end
