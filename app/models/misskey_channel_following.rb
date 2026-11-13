# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_channel_followings
#
#  id                 :bigint(8)        not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint(8)        not null
#  misskey_channel_id :bigint(8)        not null
#
class MisskeyChannelFollowing < ApplicationRecord
  belongs_to :account
  belongs_to :misskey_channel, inverse_of: :followings

  validates :misskey_channel_id, uniqueness: { scope: :account_id }
end
