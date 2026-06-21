# frozen_string_literal: true

# == Schema Information
#
# Table name: custom_emoji_mutes
#
#  id         :bigint(8)        not null, primary key
#  prefix     :string           default(""), not null
#  domain     :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#

class CustomEmojiMute < ApplicationRecord
  belongs_to :account

  PREFIX_LIMIT = 100

  normalizes :prefix, with: ->(prefix) { prefix.to_s.strip }
  normalizes :domain, with: ->(domain) { domain.to_s.downcase.strip }

  validates :prefix, presence: true, length: { maximum: PREFIX_LIMIT }
  validates :prefix, uniqueness: { scope: %i(account_id domain) }

  scope :for_account, ->(account_id) { where(account_id: account_id) }
end
