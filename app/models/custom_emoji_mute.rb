# frozen_string_literal: true

# == Schema Information
#
# Table name: custom_emoji_mutes
#
#  id               :bigint(8)        not null, primary key
#  domain           :string           default(""), not null
#  hide_in_picker   :boolean          default(FALSE), not null
#  prefix           :string           default(""), not null
#  reject_reactions :boolean          default(FALSE), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint(8)        not null
#

class CustomEmojiMute < ApplicationRecord
  belongs_to :account

  after_commit :rewrite_response_filter_cache

  PREFIX_LIMIT = 100

  normalizes :prefix, with: ->(prefix) { prefix.to_s.strip }
  normalizes :domain, with: ->(domain) { domain.to_s.downcase.strip }

  validates :prefix, presence: true, length: { maximum: PREFIX_LIMIT }
  validates :prefix, uniqueness: { scope: %i(account_id domain) }

  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def self.purge_blank_prefixes!
    where("TRIM(prefix) = ''").delete_all
  end

  def self.reaction_muted?(recipient_account_id, shortcode, domain)
    return false if recipient_account_id.blank? || shortcode.blank?

    normalized_shortcode = shortcode.to_s.downcase
    normalized_domain = domain.to_s.downcase

    for_account(recipient_account_id).where(reject_reactions: true).where.not(prefix: '').any? do |mute|
      (mute.domain.blank? || mute.domain == normalized_domain) && normalized_shortcode.start_with?(mute.prefix.downcase)
    end
  end

  private

  def rewrite_response_filter_cache
    CustomEmojiMuteCache.write(account_id)
  end
end
