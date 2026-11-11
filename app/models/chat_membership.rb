# frozen_string_literal: true

class ChatMembership < ApplicationRecord
  enum :role, { member: 0, owner: 1 }

  belongs_to :chat_conversation, inverse_of: :memberships
  belongs_to :account
  belongs_to :last_read_message, class_name: 'ChatMessage', optional: true

  validates :account_id, uniqueness: { scope: :chat_conversation_id }
  validate :last_read_message_belongs_to_conversation
  after_create :record_roster_time
  after_destroy_commit :remove_unusable_conversation
  after_destroy_commit :revoke_voice_call

  private

  def record_roster_time
    return unless chat_conversation.chat_group?

    ChatRosterState.find_or_create_by!(chat_conversation_id: chat_conversation_id, account_id: account_id)
  end

  def last_read_message_belongs_to_conversation
    return if last_read_message.nil? || last_read_message.chat_conversation_id == chat_conversation_id

    errors.add(:last_read_message, :invalid)
  end

  def revoke_voice_call
    return unless VoiceCallAllocation.unfinished.exists?(chat_conversation_id:)

    VoiceCallRevocationWorker.perform_async(chat_conversation_id, account_id)
  end

  def remove_unusable_conversation
    return if destroyed_by_association&.name == :memberships

    conversation = ChatConversation.find_by(id: chat_conversation_id)
    return if conversation.nil?
    return unless owner? || (conversation.chat_direct? && conversation.memberships.count < 2)

    conversation.destroy!
  end
end
