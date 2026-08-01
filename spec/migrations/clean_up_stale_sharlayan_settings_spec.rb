# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20260802010300_clean_up_stale_sharlayan_settings.rb')

RSpec.describe CleanUpStaleSharlayanSettings do
  describe '#up' do
    it 'removes only clip columns whose clips no longer exist' do
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

      described_class.new.up

      expect(setting.reload.data.fetch('columns').pluck('uuid')).to eq(%w(home existing list))
    end

    it 'leaves settings without a columns array unchanged' do
      setting = Web::Setting.create!(user: Fabricate(:user), data: { theme: 'mastodon-light' })

      expect { described_class.new.up }.to_not(change { setting.reload.data })
    end

    it 'removes blank custom emoji mutes while preserving valid mutes' do
      account = Fabricate(:account)
      blank_mute = account.custom_emoji_mutes.create!(prefix: 'temporary')
      valid_mute = account.custom_emoji_mutes.create!(prefix: 'blob')
      blank_mute.update_column(:prefix, ' ')

      described_class.new.up

      expect(CustomEmojiMute.where(id: blank_mute.id)).to_not exist
      expect(CustomEmojiMute.where(id: valid_mute.id)).to exist
    end
  end
end
