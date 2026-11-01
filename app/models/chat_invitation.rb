# frozen_string_literal: true

class ChatInvitation < ApplicationRecord
  enum :state, { pending: 0, accepted: 1, rejected: 2, cancelled: 3 }

  belongs_to :chat_conversation, inverse_of: :invitations
  belongs_to :inviter_account, class_name: 'Account'
  belongs_to :invitee_account, class_name: 'Account'

  validates :invitee_account_id, uniqueness: { scope: :chat_conversation_id }, if: :pending?
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
