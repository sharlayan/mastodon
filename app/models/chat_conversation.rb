# frozen_string_literal: true

class ChatConversation < ApplicationRecord
  enum :conversation_type, { direct: 0, group: 1 }, prefix: :chat

  belongs_to :owner_account, class_name: 'Account', optional: true
  belongs_to :last_message, class_name: 'ChatMessage', optional: true

  has_many :memberships, class_name: 'ChatMembership', dependent: :destroy, inverse_of: :chat_conversation
  has_many :accounts, through: :memberships
  has_many :messages, -> { order(id: :desc) }, class_name: 'ChatMessage', dependent: :destroy, inverse_of: :chat_conversation
  has_many :invitations, class_name: 'ChatInvitation', dependent: :destroy, inverse_of: :chat_conversation

  validates :direct_key, presence: true, uniqueness: true, if: :chat_direct?
  validates :direct_key, absence: true, if: :chat_group?
  validates :title, length: { maximum: 256 }, allow_blank: true
  validates :title, presence: true, if: :chat_group?
  validates :description, length: { maximum: 2048 }, allow_blank: true

  scope :for_account, ->(account) { joins(:memberships).where(chat_memberships: { account_id: account.id }) }

  def archived?
    archived_at.present?
  end
end
