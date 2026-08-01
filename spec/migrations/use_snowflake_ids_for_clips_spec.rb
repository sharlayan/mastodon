# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20260801151200_use_snowflake_ids_for_clips.rb')

RSpec.describe UseSnowflakeIdsForClips do
  describe '#migrate_legacy_ids!' do
    it 'updates existing clip IDs and their references' do
      owner = Fabricate(:account)
      clip = Clip.create!(id: 1, account: owner, title: 'Legacy clip', created_at: 1.day.ago)
      clip_status = clip.clip_statuses.create!(status: Fabricate(:status))
      favourite = Fabricate(:account).clip_favourites.create!(clip: clip)

      described_class.new.send(:migrate_legacy_ids!)

      migrated_clip = Clip.find_by!(title: 'Legacy clip')

      expect(migrated_clip.id).to_not eq(1)
      expect(Mastodon::Snowflake.to_time(migrated_clip.id)).to be_within(1.minute).of(clip.created_at)
      expect(migrated_clip.account).to eq(owner)
      expect(clip_status.reload.clip_id).to eq(migrated_clip.id)
      expect(favourite.reload.clip_id).to eq(migrated_clip.id)
    end
  end
end
