# frozen_string_literal: true

class VoiceCallMaintenanceWorker
  include Sidekiq::Worker

  sidekiq_options retry: false, lock: :until_executing, lock_ttl: 1.minute.to_i

  def perform(provider_id)
    provider = VoiceRelayProvider.find_by(id: provider_id)
    return if provider.nil?

    Sharlayan::VoiceCallService.new.maintain_provider(provider)
  end
end
