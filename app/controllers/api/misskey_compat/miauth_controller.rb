# frozen_string_literal: true

class Api::MisskeyCompat::MiauthController < Api::MisskeyCompat::BaseController
  include Redisable

  def check
    return render json: { ok: false } unless MisskeyCompat::MiAuth.valid_session?(params[:session])
    return if rate_limited?(:misskey_compat_api)

    token = with_redis { |r| r.getdel(MisskeyCompat::MiAuth.redis_key(params[:session])) }
    return render json: { ok: false } if token.blank?

    access_token = Doorkeeper::AccessToken.by_token(token)
    return render json: { ok: false } unless access_token&.accessible?

    user = User.find_by(id: access_token.resource_owner_id)
    return render json: { ok: false } if user.nil?

    render json: {
      ok: true,
      token: token,
      user: MisskeyCompat::UserSerializer.serialize(user.account, detailed: true),
    }
  end
end
