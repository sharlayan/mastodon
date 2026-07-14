# frozen_string_literal: true

module MisskeyCompat::PskeyCspConcern
  extend ActiveSupport::Concern

  PSKEY_USER_AGENT = /Pskey/i

  included do
    before_action :relax_csp_for_pskey!
  end

  private

  def relax_csp_for_pskey!
    return unless Setting.misskey_compat_enabled
    return unless pskey_webview_request?

    policy = request.content_security_policy
    return if policy.nil?

    sources = policy.directives['script-src']
    return if sources.blank? || sources.include?("'unsafe-eval'")

    request.content_security_policy = policy.clone.tap do |cloned|
      cloned.script_src(*sources, "'unsafe-eval'")
    end
  end

  def pskey_webview_request?
    request.user_agent.to_s.match?(PSKEY_USER_AGENT)
  end
end
