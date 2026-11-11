# frozen_string_literal: true

class VoiceCallEventsWorker
  include Sidekiq::Worker
  include Lockable

  POLL_INTERVAL = 2.seconds

  sidekiq_options retry: false, lock: :until_executing, lock_ttl: 1.minute.to_i

  def perform(provider_id)
    provider = VoiceRelayProvider.find_by(id: provider_id)
    return if provider.nil?

    active = with_redis_lock("voice_call_events:#{provider_id}", autorelease: 2.minutes, raise_on_failure: false) do
      Sharlayan::VoiceCallService.new.poll_events(provider)
    end

    self.class.perform_in(POLL_INTERVAL, provider_id) if active
  end
end
