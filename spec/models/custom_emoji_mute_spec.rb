# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmojiMute do
  let(:account) { Fabricate(:account) }

  describe 'per-account limit' do
    before { stub_const('CustomEmojiMute::PER_ACCOUNT_LIMIT', 2) }

    it 'rejects creation beyond the limit' do
      2.times { |index| account.custom_emoji_mutes.create!(prefix: "mute#{index}") }

      mute = account.custom_emoji_mutes.new(prefix: 'overflow')

      expect(mute).to_not be_valid
      expect(mute.errors[:base]).to include(I18n.t('custom_emoji_mutes.errors.limit'))
    end

    it 'still allows updating an existing record at the limit' do
      2.times { |index| account.custom_emoji_mutes.create!(prefix: "mute#{index}") }
      mute = account.custom_emoji_mutes.last

      expect(mute.update(reject_reactions: true)).to be true
    end

    it 'counts only the owning account' do
      2.times { |index| Fabricate(:account).custom_emoji_mutes.create!(prefix: "mute#{index}") }

      expect(account.custom_emoji_mutes.new(prefix: 'mine')).to be_valid
    end
  end
end
