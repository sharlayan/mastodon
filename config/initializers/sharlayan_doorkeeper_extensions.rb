# frozen_string_literal: true

Rails.application.config.to_prepare do
  Doorkeeper::AccessToken.has_one :misskey_access_grant,
                                  class_name: 'MisskeyAccessGrant',
                                  foreign_key: :access_token_id,
                                  inverse_of: :access_token,
                                  dependent: :destroy

  Doorkeeper::Application.has_one :misskey_app,
                                  class_name: 'MisskeyApp',
                                  foreign_key: :oauth_application_id,
                                  inverse_of: :application,
                                  dependent: :destroy
end
