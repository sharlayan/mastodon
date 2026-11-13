# frozen_string_literal: true

module MisskeyCompat
  class AuthSessionsController < ApplicationController
    before_action :require_misskey_compat_enabled!
    before_action :authenticate_user!
    before_action :set_auth_session!

    def show; end

    def create
      @auth_session.update!(user: current_user)
      @callback = callback_url

      render :done
    end

    private

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end

    def set_auth_session!
      @auth_session = MisskeyAuthSession.active.joins(application: :misskey_app).includes(application: :misskey_app).find_by(token: params[:token])
      not_found if @auth_session.nil?
    end

    def callback_url
      callback = @auth_session.application.misskey_app.callback_url
      return nil unless MisskeyCompat::MiAuth.safe_callback?(callback)

      uri = Addressable::URI.parse(callback)
      uri.query_values = (uri.query_values || {}).merge('token' => @auth_session.token)
      uri.to_s
    end
  end
end
