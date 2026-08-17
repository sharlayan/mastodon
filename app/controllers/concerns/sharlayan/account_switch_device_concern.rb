# frozen_string_literal: true

module Sharlayan::AccountSwitchDeviceConcern
  extend ActiveSupport::Concern

  DEVICE_COOKIE = :account_switch_device
  LEGACY_COOKIE = :account_switch_legacy_session
  ROLLOUT_CUTOFF = Time.utc(2026, 8, 17, 16, 37)

  private

  def account_switch_device_token
    token = cookies.encrypted[DEVICE_COOKIE]
    return token if token.present?

    token = SecureRandom.urlsafe_base64(48)
    cookies.encrypted[DEVICE_COOKIE] = {
      value: token,
      httponly: true,
      secure: Rails.configuration.x.use_https,
      same_site: :lax,
    }
    token
  end

  def account_switch_device_digest
    key = OpenSSL::HMAC.digest('SHA256', Rails.application.secret_key_base, 'account-switch-device-digest')
    OpenSSL::HMAC.hexdigest('SHA256', key, account_switch_device_token)
  end

  def find_or_record_account_switch_device(account, trust: false)
    now = Time.current
    device = AccountSwitchDevice.find_or_initialize_by(account:, token_digest: account_switch_device_digest)
    device.first_seen_at ||= now
    device.first_seen_ip ||= request.remote_ip
    device.last_seen_at = now
    device.last_seen_ip = request.remote_ip
    device.user_agent = request.user_agent.to_s.first(1_024)
    device.session_activation = current_session if current_session
    device.trusted_at ||= now if trust
    device.revoked_at = nil if trust
    device.save!
    device
  end

  def trust_account_switch_device(account)
    device = find_or_record_account_switch_device(account, trust: true)
    AccountSwitchDeviceApproval.pending.where(account_switch_device: device).delete_all
    device
  end

  def bind_account_switch_device_to_current_session(device)
    session_activation = SessionActivation.find_by(session_id: cookies.signed['_session_id'])
    device.update!(session_activation:) if session_activation
  end

  def legacy_account_switch_session?
    return true if cookies.encrypted[LEGACY_COOKIE] == true
    return false unless current_session&.created_at&.before?(ROLLOUT_CUTOFF)

    cookies.encrypted[LEGACY_COOKIE] = {
      value: true,
      httponly: true,
      secure: Rails.configuration.x.use_https,
      same_site: :lax,
    }
    true
  end

  def masked_account_switch_ip(address)
    return if address.blank?

    ip = IPAddr.new(address.to_s)
    ip.ipv4? ? "#{ip.mask(24)}/24" : "#{ip.mask(64)}/64"
  end

  def account_switch_device_label(user_agent)
    detection = Browser.new(user_agent.to_s)
    I18n.t(
      'sessions.description',
      browser: I18n.t(detection.id, scope: 'sessions.browsers', default: detection.name),
      platform: I18n.t(detection.platform.id, scope: 'sessions.platforms', default: detection.platform.name)
    )
  end
end
