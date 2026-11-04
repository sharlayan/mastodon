# frozen_string_literal: true

class ChatMessage < ApplicationRecord
  attr_accessor :pending_media_attachments

  belongs_to :chat_conversation, inverse_of: :messages
  belongs_to :account
  belongs_to :reply_to, class_name: 'ChatMessage', optional: true

  has_many :reactions, class_name: 'ChatMessageReaction', dependent: :destroy, inverse_of: :chat_message
  has_many :chat_message_media_attachments, dependent: :destroy
  has_many :media_attachments, through: :chat_message_media_attachments

  MAX_TEXT_LENGTH = 4096

  validates :text, length: { maximum: MAX_TEXT_LENGTH }, allow_nil: true
  validates :uri, uniqueness: true, allow_nil: true
  validate :content_present
  validate :sender_is_member, on: :create
  validate :reply_belongs_to_conversation

  before_destroy :destroy_chat_media_attachments, prepend: true

  scope :visible, -> { where(deleted_at: nil) }
  scope :visible_to, ->(account) { where.not(account_id: account.id).or(where(hidden_at: nil)) }

  def deleted?
    deleted_at.present?
  end

  def hidden?
    hidden_at.present?
  end

  def remote?
    account.remote?
  end

  private

  def content_present
    errors.add(:text, :blank) if text.blank? && pending_media_attachments.blank? && media_attachments.empty? && !deleted?
  end

  def sender_is_member
    return if chat_conversation&.memberships&.any? { |membership| membership.account_id == account_id }

    errors.add(:account, :invalid)
  end

  def reply_belongs_to_conversation
    return if reply_to.nil? || reply_to.chat_conversation_id == chat_conversation_id

    errors.add(:reply_to, :invalid)
  end

  def destroy_chat_media_attachments
    media_attachments.to_a.each do |media|
      media.destroy! if media.removable_with_chat_message?
    end
  end
end
