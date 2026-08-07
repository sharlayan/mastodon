# frozen_string_literal: true

# == Schema Information
#
# Table name: status_reactions
#
#  id              :bigint(8)        not null, primary key
#  name            :string           default(""), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint(8)        not null
#  custom_emoji_id :bigint(8)
#  status_id       :bigint(8)        not null
#
class StatusReaction < ApplicationRecord
  include Paginable

  update_index('statuses', :status)

  belongs_to :account, inverse_of: :status_reactions
  belongs_to :status, inverse_of: :status_reactions
  belongs_to :custom_emoji, optional: true

  has_one :notification, as: :activity, dependent: :destroy

  validates :status_id, uniqueness: { scope: [:account_id, :name] }
  validates :name, presence: true

  validates_with StatusReactionValidator

  before_validation :set_custom_emoji
  before_validation do
    self.status = status.reblog if status&.reblog?
  end

  after_create :increment_cache_counters
  after_destroy :decrement_cache_counters
  after_destroy :invalidate_cleanup_info

  USERS_DISPLAY_LIMIT = 11

  def users
    return @preloaded_users if defined?(@preloaded_users)

    account_ids = StatusReaction.where(status_id: status_id, name: name, custom_emoji_id: custom_emoji_id).select(:account_id)
    Account.where(id: account_ids).limit(USERS_DISPLAY_LIMIT)
  end

  def account_ids
    return @preloaded_account_ids if defined?(@preloaded_account_ids)

    StatusReaction.where(status_id: status_id, name: name, custom_emoji_id: custom_emoji_id).pluck(:account_id).map(&:to_s)
  end

  def preloaded_account_ids=(ids)
    @preloaded_account_ids = ids.map(&:to_s)
  end

  attr_writer :preloaded_users

  private

  def set_custom_emoji
    self.custom_emoji = CustomEmoji.find_by(disabled: false, shortcode: name, domain: custom_emoji.domain) if name.present? && custom_emoji.present?
  end

  def increment_cache_counters
    status&.increment_count!(:reactions_count)
  end

  def decrement_cache_counters
    return if association(:status).loaded? && status.marked_for_destruction?

    status&.decrement_count!(:reactions_count)
  end

  def invalidate_cleanup_info
    return unless status&.account_id == account_id && account.local?

    account.statuses_cleanup_policy&.invalidate_last_inspected(status, :unreact)
  end
end
