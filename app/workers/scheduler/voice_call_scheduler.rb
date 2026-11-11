# frozen_string_literal: true

class Scheduler::VoiceCallScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 5.minutes.to_i

  def perform
    Sharlayan::VoiceCallService.new.maintain
  end
end
