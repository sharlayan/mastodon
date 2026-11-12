# frozen_string_literal: true

class VoiceCallMirrorClearWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, lock: :until_executing, lock_ttl: 1.hour.to_i

  def perform
    Sharlayan::VoiceCallFederation::RemoteStates.clear
  end
end
