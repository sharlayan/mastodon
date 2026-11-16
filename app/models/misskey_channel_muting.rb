# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_channel_mutings
#
#  id                 :bigint(8)        not null, primary key
#  expires_at         :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint(8)        not null
#  misskey_channel_id :bigint(8)        not null
#
class MisskeyChannelMuting < ApplicationRecord
  belongs_to :account
  belongs_to :misskey_channel, inverse_of: :mutings

  scope :active, -> { where(expires_at: nil).or(where(arel_table[:expires_at].gt(Time.now.utc))) }

  validates :misskey_channel_id, uniqueness: { scope: :account_id }

  def self.channel_ids_for(account)
    return [] if account.nil?

    active.where(account: account).pluck(:misskey_channel_id)
  end

  def expired?
    expires_at.present? && expires_at <= Time.now.utc
  end
end
