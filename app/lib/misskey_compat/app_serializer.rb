# frozen_string_literal: true

module MisskeyCompat::AppSerializer
  module_function

  def serialize(application, viewer: nil, include_secret: false)
    misskey_app = application.misskey_app

    {
      id: MisskeyCompat::MiId.encode(application.id),
      name: application.name,
      callbackUrl: misskey_app&.callback_url,
      permission: misskey_app&.permission || [],
    }.tap do |data|
      data[:secret] = application.secret if include_secret
      data[:isAuthorized] = authorized?(application, viewer) unless viewer.nil?
    end
  end

  def authorized?(application, user)
    Doorkeeper::AccessToken.not_revoked.exists?(application_id: application.id, resource_owner_id: user.id)
  end
end
