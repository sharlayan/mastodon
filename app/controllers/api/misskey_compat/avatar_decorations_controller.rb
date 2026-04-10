# frozen_string_literal: true

class Api::MisskeyCompat::AvatarDecorationsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def index
    return render json: [] unless Setting.avatar_decorations_enabled &&
                                  Setting.avatar_decorations_federation_enabled

    decorations = AvatarDecoration.local.approved

    render json: decorations.map { |d|
      {
        id: d.id.to_s,
        name: d.name,
        description: d.description.presence || '',
        url: d.image_url,
        roleIdsThatCanBeUsedThisDecoration: d.required_role_id ? [d.required_role_id.to_s] : [],
      }
    }
  end
end
