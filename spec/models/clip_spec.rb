# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Clip do
  describe 'stream invalidation' do
    it 'broadcasts metadata, membership and deletion changes through the shared model' do
      clip = Fabricate(:clip)
      allow(MisskeyCompat::Streaming).to receive(:broadcast_clip)

      clip.update!(title: 'Updated')
      membership = clip.clip_statuses.create!(status: Fabricate(:status))
      membership.destroy!
      expect(MisskeyCompat::Streaming).to have_received(:broadcast_clip).with(anything, clip, 'updated').exactly(3).times

      clip.destroy!
      expect(MisskeyCompat::Streaming).to have_received(:broadcast_clip).with(anything, clip, 'deleted').once
    end
  end

  describe 'ID generation' do
    it 'uses a timestamp-based ID' do
      clip = described_class.create!(account: Fabricate(:account), title: 'Clip')

      expect(Mastodon::Snowflake.to_time(clip.id)).to be_within(1.minute).of(Time.current)
    end
  end
end
