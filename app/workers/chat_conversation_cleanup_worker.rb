# frozen_string_literal: true

class ChatConversationCleanupWorker
  include Sidekiq::Worker

  CLEANUP_DELAY = 30.days

  sidekiq_options queue: 'default', retry: 3

  def perform(conversation_id)
    conversation = ChatConversation.find_by(id: conversation_id)
    return if conversation.nil?
    return unless conversation.remote?
    return if conversation.accounts.local.exists?

    newest_invitation = conversation.invitations.pending.maximum(:created_at)
    return self.class.perform_at(newest_invitation + CLEANUP_DELAY, conversation_id) if newest_invitation && newest_invitation > CLEANUP_DELAY.ago

    Sharlayan::ChatService.new.remove_abandoned_conversation(conversation)
  end
end
