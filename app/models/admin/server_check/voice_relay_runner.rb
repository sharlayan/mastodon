# frozen_string_literal: true

class Admin::ServerCheck::VoiceRelayRunner
  include Admin::ServerCheck::Runner

  def async?
    false
  end

  def authorized?(user)
    user.can?(:manage_settings) && Sharlayan::VoiceCallService.enabled?
  end

  def run
    if revoked_providers.any?
      pending(data: { reason: :revoked, providers_str: revoked_providers.join(', ') }, severity: :critical)
    elsif VoiceRelayProvider.usable.exists?
      ok
    else
      pending(data: { reason: :unavailable }, severity: :warning)
    end
  end

  private

  def revoked_providers
    @revoked_providers ||= VoiceRelayProvider.where(enabled: true).where.not(revoked_at: nil).order(:id).pluck(:origin)
  end
end
