# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20260802010300_clean_up_stale_sharlayan_settings.rb')

RSpec.describe CleanUpStaleSharlayanSettings do
  describe '#up' do
    it 'removes only missing clip columns and blank custom emoji mutes, leaving other settings and mutes unchanged' do
      user = Fabricate(:user)
      clip = Fabricate(:clip, account: user.account)
      setting = Web::Setting.create!(
        user: user,
        data: {
          columns: [
            { id: 'HOME', uuid: 'home', params: {} },
            { id: 'CLIP', uuid: 'existing', params: { id: clip.id.to_s } },
            { id: 'CLIP', uuid: 'missing', params: { id: '1' } },
            { id: 'LIST', uuid: 'list', params: { id: '1' } },
          ],
        }
      )
      columnless_setting = Web::Setting.create!(user: Fabricate(:user), data: { theme: 'mastodon-light' })
      blank_mute = user.account.custom_emoji_mutes.create!(prefix: 'temporary')
      valid_mute = user.account.custom_emoji_mutes.create!(prefix: 'blob')
      blank_mute.update_column(:prefix, ' ')

      expect { described_class.new.up }.to_not(change { columnless_setting.reload.data })
      expect(setting.reload.data.fetch('columns').pluck('uuid')).to eq(%w(home existing list))
      expect(CustomEmojiMute.where(id: blank_mute.id)).to_not exist
      expect(CustomEmojiMute.where(id: valid_mute.id)).to exist
    end
  end
end
