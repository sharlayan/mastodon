# frozen_string_literal: true

# == Schema Information
#
# Table name: reaction_mutes
#
#  id                :bigint(8)        not null, primary key
#  target_domain     :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint(8)        not null
#  target_account_id :bigint(8)
#
#  id                :bigint(8)        not null, primary key
#  target_domain     :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint(8)        not null
#  target_account_id :bigint(8)

class ReactionMute < ApplicationRecord
  belongs_to :account
  belongs_to :target_account, class_name: 'Account', optional: true, inverse_of: :reaction_mutes_targeting_account

  validates :account_id, uniqueness: { scope: :target_account_id }, if: -> { target_account_id.present? }
  validates :account_id, uniqueness: { scope: :target_domain }, if: -> { target_domain.present? }
  validate :exactly_one_target

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_target_account, ->(target_account_id) { where(target_account_id: target_account_id) }
  scope :by_target_domain, ->(domain) { where(target_domain: domain) }

  def self.muted?(recipient_account_id, reactor)
    return false if recipient_account_id.blank? || reactor.nil?

    mutes = for_account(recipient_account_id)
    return true if mutes.by_target_account(reactor.id).exists?

    reactor.domain.present? && mutes.by_target_domain(reactor.domain).exists?
  end

  private

  def exactly_one_target
    if target_account_id.present? && target_domain.present?
      errors.add(:base, 'cannot set both target_account_id and target_domain')
    elsif target_account_id.blank? && target_domain.blank?
      errors.add(:base, 'must set either target_account_id or target_domain')
    end
  end
end
