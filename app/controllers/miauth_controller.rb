# frozen_string_literal: true

class MiauthController < ApplicationController
  include Redisable

  before_action :require_misskey_compat_enabled!
  before_action :authenticate_user!
  before_action :set_session!
  before_action :validate_callback!

  def show
    @app_name = params[:name]
    @callback = params[:callback]
    @permission = params[:permission]
  end

  def create
    return if issuance_rate_limited?

    token = MisskeyCompat::MiAuth.issue_token(current_user, permission: params[:permission], name: params[:name], callback: params[:callback])
    with_redis { |r| r.set(MisskeyCompat::MiAuth.redis_key(@session), token.token, ex: MisskeyCompat::MiAuth::SESSION_TTL.to_i) }

    @callback = build_callback
    render :done
  end

  private

  def issuance_rate_limited?
    recorded_limiters = []

    %i(misskey_miauth_hourly misskey_miauth_daily).each do |family|
      limiter = RateLimiter.new(current_account, family: family)
      limiter.record!
      recorded_limiters << limiter
    end

    false
  rescue Mastodon::RateLimitExceededError
    recorded_limiters.each(&:rollback!)
    render plain: I18n.t('errors.429'), status: 429
    true
  end

  def build_callback
    return nil if params[:callback].blank?
    return nil unless MisskeyCompat::MiAuth.safe_callback?(params[:callback])

    append_session(params[:callback])
  end

  def require_misskey_compat_enabled!
    not_found unless Setting.misskey_compat_enabled
  end

  def set_session!
    @session = params[:session]
    not_found unless MisskeyCompat::MiAuth.valid_session?(@session)
  end

  def validate_callback!
    return if params[:callback].blank? || MisskeyCompat::MiAuth.safe_callback?(params[:callback])

    render plain: I18n.t('errors.400'), status: 400
  end

  def append_session(callback)
    uri = Addressable::URI.parse(callback)
    query = uri.query_values || {}
    uri.query_values = query.merge('session' => @session)
    uri.to_s
  end
end
