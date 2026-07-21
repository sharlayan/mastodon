# frozen_string_literal: true

class MiauthController < ApplicationController
  include Redisable

  before_action :require_misskey_compat_enabled!
  before_action :authenticate_user!
  before_action :set_session!

  def show
    @app_name = params[:name]
    @callback = params[:callback]
    @permission = params[:permission]
  end

  def create
    token = MisskeyCompat::MiAuth.issue_token(current_user, permission: params[:permission], name: params[:name], callback: params[:callback])
    with_redis { |r| r.set(MisskeyCompat::MiAuth.redis_key(@session), token.token, ex: MisskeyCompat::MiAuth::SESSION_TTL.to_i) }

    @callback = build_callback
    render :done
  end

  private

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

  def append_session(callback)
    uri = Addressable::URI.parse(callback)
    query = uri.query_values || {}
    uri.query_values = query.merge('session' => @session)
    uri.to_s
  end
end
