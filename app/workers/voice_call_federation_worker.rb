# frozen_string_literal: true

class VoiceCallFederationWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'push', retry: 3, lock: :until_executing, lock_ttl: 1.minute.to_i

  def perform(conversation_id)
    conversation = ChatConversation.find_by(id: conversation_id)
    return if conversation.nil?

    Sharlayan::VoiceCallFederation::Outgoing.publish(conversation)
  end
end
