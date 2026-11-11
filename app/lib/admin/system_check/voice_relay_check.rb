# frozen_string_literal: true

class Admin::SystemCheck::VoiceRelayCheck < Admin::SystemCheck::BaseCheck
  include RoutingHelper

  def skip?
    !current_user.can?(:manage_settings) || !Sharlayan::VoiceCallService.enabled?
  end

  def pass?
    revoked_providers.empty? && VoiceRelayProvider.usable.exists?
  end

  def message
    if revoked_providers.any?
      Admin::SystemCheck::Message.new(:voice_relay_revoked_check, revoked_providers.join(', '), admin_voice_relay_providers_path, critical: true)
    else
      Admin::SystemCheck::Message.new(:voice_relay_unavailable_check, nil, admin_voice_relay_providers_path)
    end
  end

  private

  def revoked_providers
    @revoked_providers ||= VoiceRelayProvider.where(enabled: true).where.not(revoked_at: nil).order(:id).pluck(:origin)
  end
end
