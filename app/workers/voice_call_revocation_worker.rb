# frozen_string_literal: true

class VoiceCallRevocationWorker
  include Sidekiq::Worker

  sidekiq_options retry: 5

  def perform(conversation_id, account_id)
    Sharlayan::VoiceCallService.new.revoke(conversation_id, account_id)
  end
end
