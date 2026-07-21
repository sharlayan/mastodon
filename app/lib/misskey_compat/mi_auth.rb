# frozen_string_literal: true

module MisskeyCompat::MiAuth
  SESSION_TTL = 5.minutes
  APP_NAME = 'Misskey (MiAuth)'
  SCOPES = 'read write follow push'
  TOKEN_TTL = 30.days
  WRITE_PERMISSIONS = %w(
    write:account write:blocks write:drive write:favorites write:following
    write:mutes write:notes write:notifications write:pages write:reactions
    write:votes
  ).freeze
  UNSAFE_CALLBACK_SCHEMES = %w(javascript file data mailto tel vbscript).freeze

  module_function

  def redis_key(session)
    "misskey_compat:miauth:#{session}"
  end

  def valid_session?(session)
    value = session.to_s
    value.length <= 64 && value.match?(/\A[0-9a-fA-F-]+\z/) && value.delete('-').length >= 32
  end

  def legacy_token?(token)
    token.application&.name == APP_NAME && token.expires_in.nil?
  end

  def safe_callback?(callback)
    return false if callback.blank?

    uri = Addressable::URI.parse(callback)
    uri.scheme.present? && UNSAFE_CALLBACK_SCHEMES.exclude?(uri.scheme.downcase)
  rescue Addressable::URI::InvalidURIError
    false
  end

  def application(name: nil, callback: nil)
    identity = Digest::SHA256.hexdigest([name, callback].join("\0"))[0, 16]
    display_name = name.to_s.strip.presence || 'Unnamed client'
    application_name = "#{APP_NAME}: #{display_name.truncate(80)} [#{identity}]"

    Doorkeeper::Application.find_or_create_by!(name: application_name) do |app|
      app.redirect_uri = Doorkeeper.config.native_redirect_uri
      app.scopes = SCOPES
    end
  end

  def scopes_for(permission)
    permissions = permission.to_s.split(',').map(&:strip).compact_blank
    scopes = ['read']
    scopes << 'write' if (permissions & WRITE_PERMISSIONS).any?
    scopes << 'follow' if permissions.any? { |value| value.end_with?(':following') }
    scopes.join(' ')
  end

  def issue_token(user, permission: nil, name: nil, callback: nil, scopes: nil)
    Doorkeeper::AccessToken.create!(
      application: application(name: name, callback: callback),
      resource_owner_id: user.id,
      scopes: scopes || scopes_for(permission),
      expires_in: TOKEN_TTL.to_i,
      use_refresh_token: false
    )
  end
end
