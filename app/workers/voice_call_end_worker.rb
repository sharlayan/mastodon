# frozen_string_literal: true

class VoiceCallEndWorker
  include Sidekiq::Worker

  sidekiq_options retry: 5

  def perform(allocation_id)
    allocation = VoiceCallAllocation.find_by(id: allocation_id)
    return if allocation.nil? || allocation.ended?

    Sharlayan::VoiceCallService.new.end_call(allocation)
  end
end
