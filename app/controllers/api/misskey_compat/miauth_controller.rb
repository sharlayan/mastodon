# frozen_string_literal: true

class Api::MisskeyCompat::MiauthController < Api::MisskeyCompat::BaseController
  include Redisable

  def check
    token = with_redis { |r| r.get(MisskeyCompat::MiAuth.redis_key(params[:session])) }
    return render json: { ok: false } if token.blank?

    access_token = Doorkeeper::AccessToken.by_token(token)
    return render json: { ok: false } if access_token.nil? || access_token.revoked?

    user = User.find_by(id: access_token.resource_owner_id)
    return render json: { ok: false } if user.nil?

    with_redis { |r| r.del(MisskeyCompat::MiAuth.redis_key(params[:session])) }

    render json: {
      ok: true,
      token: token,
      user: MisskeyCompat::UserSerializer.serialize(user.account, detailed: true),
    }
  end
end
