# frozen_string_literal: true

class Api::MisskeyCompat::AvatarDecorationsController < Api::MisskeyCompat::BaseController
  include RoutingHelper

  def index
    return render json: [] unless Setting.avatar_decorations_enabled &&
                                  Setting.avatar_decorations_federation_enabled &&
                                  !Setting.avatar_decorations_local_only_view
    return if rate_limited?(:misskey_users_show)

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
end
