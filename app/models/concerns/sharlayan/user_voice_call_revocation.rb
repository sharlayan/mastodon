# frozen_string_literal: true

module Sharlayan::UserVoiceCallRevocation
  extend ActiveSupport::Concern

  included do
    after_update_commit :revoke_voice_calls, if: -> { (saved_change_to_disabled? && disabled?) || saved_change_to_role_id? }
  end

  private

  def revoke_voice_calls
    Sharlayan::VoiceCallService.revoke_account_calls(account_id) unless account_id.nil?
  end
end
