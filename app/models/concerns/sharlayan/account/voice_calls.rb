# frozen_string_literal: true

module Sharlayan::Account::VoiceCalls
  extend ActiveSupport::Concern

  included do
    after_update_commit :revoke_voice_calls, if: -> { saved_change_to_suspended_at? && suspended_at.present? }
  end

  private

  def revoke_voice_calls
    Sharlayan::VoiceCallService.revoke_account_calls(id)
  end
end
