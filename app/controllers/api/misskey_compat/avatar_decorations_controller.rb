# frozen_string_literal: true

class Api::MisskeyCompat::AvatarDecorationsController < ApplicationController
  include RoutingHelper

  RequesterIdentity = Struct.new(:id)

  skip_before_action :verify_authenticity_token, raise: false

  def index
    return render json: [] unless Setting.avatar_decorations_enabled &&
                                  Setting.avatar_decorations_federation_enabled &&
                                  !Setting.avatar_decorations_local_only_view
    return if rate_limited_by_ip?

    decorations = AvatarDecoration.local.approved

    render json: decorations.map { |d|
      {
        id: MisskeyCompat::MiId.encode(d.id),
        name: d.name,
        description: d.description.presence || '',
        url: full_asset_url(d.image_url),
        roleIdsThatCanBeUsedThisDecoration: d.required_role_id ? [MisskeyCompat::MiId.encode(d.required_role_id)] : [],
      }
    }
  end

  private

  def rate_limited_by_ip?
    RateLimiter.new(RequesterIdentity.new(request.remote_ip), family: :misskey_users_show).record!
    false
  rescue Mastodon::RateLimitExceededError
    render json: { error: I18n.t('errors.429') }, status: 429
    true
  end
end
