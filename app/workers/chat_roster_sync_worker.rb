# frozen_string_literal: true

class ChatRosterSyncWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 3, dead: false, lock: :until_executed, lock_ttl: 1.hour.to_i

  def perform(conversation_id)
    conversation = ChatConversation.find_by(id: conversation_id)
    return if conversation.nil?

    Sharlayan::ChatFederation::Roster.sync(conversation)
  end
end
