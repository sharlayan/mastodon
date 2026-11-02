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

    conversation.destroy!
  end
end
