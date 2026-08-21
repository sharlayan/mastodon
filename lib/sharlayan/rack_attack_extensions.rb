# frozen_string_literal: true

module Sharlayan
  module RackAttackExtensions
    MULTI_ACCOUNT_AUTH_PATHS = ['/multi_accounts/auth/sign_in', '/multi_accounts/auth/verify_otp'].freeze
    MISSKEY_SIGNIN_PATH = '/api/signin-flow'
    MISSKEY_URL_PREVIEW_PATH = '/url'
    MEDIA_PROXY_PATH_REGEX = %r{\A/(?:media_proxy|proxy)(?:/|\z)}

    module RequestMethods
      def bypasses_rate_limit?
        return @bypasses_rate_limit if defined?(@bypasses_rate_limit)

        @bypasses_rate_limit = if Setting.rate_limit_bypass_enabled
                                 authenticated_user&.can_extra?(:bypass_rate_limit) || false
                               else
                                 false
                               end
      end

      def role_rate_limit(name)
        authenticated_user&.role&.rate_limit_for(name) || UserRole::RATE_LIMITS.fetch(name)[:default]
      end

      def authenticated_user
        return @authenticated_user if defined?(@authenticated_user)

        @authenticated_user = User.includes(:role).find_by(id: authenticated_user_id)
      end
    end

    module_function

    def apply(attack)
      attack.const_get(:Request).prepend(RequestMethods)
      register_api_throttles(attack)
      register_feature_throttles(attack)
      register_multi_account_throttles(attack)
    end

    def register_api_throttles(attack)
      attack.throttle('throttle_authenticated_api', limit: ->(req) { req.role_rate_limit(:api) }, period: 5.minutes) do |req|
        req.authenticated_user_id if req.api_request? && !req.bypasses_rate_limit?
      end

      attack.throttle('throttle_per_token_api', limit: ->(req) { req.role_rate_limit(:api_token) }, period: 5.minutes) do |req|
        req.authenticated_token_id if req.api_request? && !req.bypasses_rate_limit?
      end

      attack.throttle('throttle_api_media', limit: ->(req) { req.role_rate_limit(:api_media) }, period: 30.minutes) do |req|
        req.authenticated_user_id if req.post? && req.path.match?(%r{\A/api/v\d+/media\z}i) && !req.bypasses_rate_limit?
      end

      attack.throttle('throttle_media_proxy', limit: 100, period: 10.minutes) do |req|
        req.throttleable_remote_ip if req.path.match?(MEDIA_PROXY_PATH_REGEX)
      end

      attack.throttle('throttle_misskey_url_preview', limit: 100, period: 10.minutes) do |req|
        req.throttleable_remote_ip if req.get? && req.path == MISSKEY_URL_PREVIEW_PATH
      end

      attack.throttle('throttle_authenticated_paging', limit: ->(req) { req.role_rate_limit(:api_paging) }, period: 15.minutes) do |req|
        req.authenticated_user_id if req.paging_request? && !req.bypasses_rate_limit?
      end

      attack.throttle('throttle_api_delete', limit: ->(req) { req.role_rate_limit(:api_delete) }, period: 30.minutes) do |req|
        next if req.bypasses_rate_limit?

        reblog_path = attack.const_get(:API_DELETE_REBLOG_REGEX)
        status_path = attack.const_get(:API_DELETE_STATUS_REGEX)
        req.authenticated_user_id if (req.post? && req.path.match?(reblog_path)) || (req.delete? && req.path.match?(status_path))
      end
    end

    def register_feature_throttles(attack)
      attack.throttle('throttle_drive_uploads', limit: ->(req) { req.role_rate_limit(:drive_upload) }, period: 30.minutes) do |req|
        next unless req.post? && req.path.match?(%r{\A/api/(?:v1/drive/files(?:/upload_from_url)?|drive/files/(?:create|upload-from-url))\z}i) && !req.bypasses_rate_limit?

        req.authenticated_user_id ? "user:#{req.authenticated_user_id}" : "ip:#{req.throttleable_remote_ip}"
      end

      attack.throttle('throttle_page_password_attempts', limit: 10, period: 5.minutes) do |req|
        "#{req.authenticated_user_id || req.throttleable_remote_ip}:#{req.path}" if req.post? && req.path.match?(%r{\A/api/v1/pages/\d+/unlock\z})
      end

      attack.throttle('throttle_misskey_signin_attempts/ip', limit: 25, period: 5.minutes) do |req|
        req.throttleable_remote_ip if req.post? && req.path == MISSKEY_SIGNIN_PATH
      end

      attack.throttle('throttle_misskey_signin_attempts/username', limit: 25, period: 1.hour) do |req|
        req.params['username'].to_s.strip.delete_prefix('@').downcase.presence if req.post? && req.path == MISSKEY_SIGNIN_PATH
      end
    end

    def register_multi_account_throttles(attack)
      attack.throttle('throttle_multi_account_login_attempts/ip', limit: 25, period: 5.minutes) do |req|
        req.throttleable_remote_ip if req.post? && MULTI_ACCOUNT_AUTH_PATHS.include?(req.path)
      end

      attack.throttle('throttle_multi_account_login_attempts/email', limit: 25, period: 1.hour) do |req|
        req.params.dig('user', 'email').presence if req.post? && req.path == '/multi_accounts/auth/sign_in'
      end

      attack.throttle('throttle_multi_account_login_attempts/state', limit: 10, period: 15.minutes) do |req|
        req.params['state'].presence if req.post? && MULTI_ACCOUNT_AUTH_PATHS.include?(req.path)
      end
    end
  end
end
