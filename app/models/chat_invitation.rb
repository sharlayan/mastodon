# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_invitations
#
#  id                   :bigint(8)        not null, primary key
#  ignored              :boolean          default(FALSE), not null
#  invite_published_at  :datetime
#  state                :integer          default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  chat_conversation_id :bigint(8)        not null
#  invitee_account_id   :bigint(8)        not null
#  inviter_account_id   :bigint(8)        not null
#
class ChatInvitation < ApplicationRecord
  enum :state, { pending: 0, accepted: 1, rejected: 2, cancelled: 3 }

  belongs_to :chat_conversation, inverse_of: :invitations
  belongs_to :inviter_account, class_name: 'Account'
  belongs_to :invitee_account, class_name: 'Account'

  scope :from_available_inviters, -> { where(inviter_account_id: Account.where(suspended_at: nil).select(:id)) }

  validates :invitee_account_id, uniqueness: { scope: :chat_conversation_id, conditions: -> { pending } }, if: :pending?
  validate :group_conversation
  validate :different_accounts

  private

  def group_conversation
    errors.add(:chat_conversation, :invalid) unless chat_conversation&.chat_group?
  end

  def different_accounts
    errors.add(:invitee_account, :invalid) if inviter_account_id == invitee_account_id
  end
end
