# frozen_string_literal: true

Rails.application.config.to_prepare do
  Doorkeeper::AccessToken.has_one :misskey_access_grant,
                                  class_name: 'MisskeyAccessGrant',
                                  foreign_key: :access_token_id,
                                  inverse_of: :access_token,
                                  dependent: :destroy
end
