# frozen_string_literal: true

module MisskeyCompat::MiAuth
  SESSION_TTL = 5.minutes
  APP_NAME = 'Misskey (MiAuth)'
  SCOPES = 'read write follow push'
  UNSAFE_CALLBACK_SCHEMES = %w(javascript file data mailto tel vbscript).freeze

  module_function

  def redis_key(session)
    "misskey_compat:miauth:#{session}"
  end

  def valid_session?(session)
    value = session.to_s
    value.length <= 64 && value.match?(/\A[0-9a-fA-F-]+\z/) && value.delete('-').length >= 32
  end

  def safe_callback?(callback)
    return false if callback.blank?

    uri = Addressable::URI.parse(callback)
    uri.scheme.present? && UNSAFE_CALLBACK_SCHEMES.exclude?(uri.scheme.downcase)
  rescue Addressable::URI::InvalidURIError
    false
  end

  def application
    Doorkeeper::Application.find_or_create_by!(name: APP_NAME) do |app|
      app.redirect_uri = Doorkeeper.config.native_redirect_uri
      app.scopes = SCOPES
    end
  end

  def issue_token(user)
    Doorkeeper::AccessToken.create!(
      application: application,
      resource_owner_id: user.id,
      scopes: SCOPES,
      expires_in: nil,
      use_refresh_token: false
    )
  end
end
