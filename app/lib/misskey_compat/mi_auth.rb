# frozen_string_literal: true

module MisskeyCompat::MiAuth
  SESSION_TTL = 5.minutes
  APP_NAME = 'Misskey (MiAuth)'
  TOKEN_SCOPE = 'misskey'
  TOKEN_TTL = 30.days
  UNSAFE_CALLBACK_SCHEMES = %w(http javascript file data mailto tel vbscript).freeze
  SUPPORTED_PERMISSIONS = %w(
    read:account write:account
    read:blocks write:blocks
    read:drive write:drive
    read:favorites write:favorites
    read:following write:following
    read:mutes write:mutes
    write:notes
    read:notifications write:notifications
    read:reactions write:reactions
    write:votes
    read:pages write:pages
    read:page-likes write:page-likes
    read:clip-favorite write:clip-favorite
    write:report-abuse
  ).freeze

  module_function

  def redis_key(session)
    "misskey_compat:miauth:#{session}"
  end

  def valid_session?(session)
    value = session.to_s
    value.length <= 64 && value.match?(/\A[0-9a-fA-F-]+\z/) && value.delete('-').length >= 32
  end

  def legacy_token?(token)
    miauth_token?(token) && token.misskey_access_grant.nil?
  end

  def miauth_token?(token)
    name = token.application&.name.to_s
    name == APP_NAME || name.start_with?("#{APP_NAME}:")
  end

  def safe_callback?(callback)
    return false if callback.blank?

    uri = Addressable::URI.parse(callback)
    scheme = uri.scheme&.downcase
    return false if scheme.blank? || UNSAFE_CALLBACK_SCHEMES.include?(scheme) || uri.userinfo.present?

    scheme != 'https' || uri.host.present?
  rescue Addressable::URI::InvalidURIError
    false
  end

  def application(name: nil, callback: nil)
    identity = Digest::SHA256.hexdigest([name, callback].join("\0"))[0, 16]
    display_name = name.to_s.strip.presence || 'Unnamed client'
    application_name = "#{APP_NAME}: #{display_name.truncate(80)} [#{identity}]"

    Doorkeeper::Application.find_or_initialize_by(name: application_name).tap do |app|
      app.redirect_uri ||= Doorkeeper.config.native_redirect_uri
      app.scopes = TOKEN_SCOPE
      app.save! if app.changed?
    end
  end

  def normalize_permissions(permission)
    values = permission.is_a?(Array) ? permission : permission.to_s.split(',')
    values.map { |value| value.to_s.strip }.compact_blank.uniq & SUPPORTED_PERMISSIONS
  end

  def issue_token(user, permission: nil, name: nil, callback: nil, permissions: nil)
    normalized_permissions = normalize_permissions(permissions || permission)

    Doorkeeper::AccessToken.transaction do
      token = Doorkeeper::AccessToken.create!(
        application: application(name: name, callback: callback),
        resource_owner_id: user.id,
        scopes: TOKEN_SCOPE,
        expires_in: TOKEN_TTL.to_i,
        use_refresh_token: false
      )
      token.create_misskey_access_grant!(permissions: normalized_permissions)
      token
    end
  end
end
