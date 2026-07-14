# frozen_string_literal: true

module MisskeyCompat
  class AvatarsController < ApplicationController
    include RoutingHelper

    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    def show
      account = resolve_account(params[:acct].to_s)
      url = account&.avatar_original_url

      return not_found if url.blank?

      expires_in 1.hour, public: true
      redirect_to full_asset_url(url), allow_other_host: true, status: 302
    end

    private

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end

    def resolve_account(acct)
      username, domain = acct.delete_prefix('@').split('@', 2)
      return nil if username.blank?

      domain = nil if local_domain?(domain)
      Account.find_remote(username, domain)
    end

    def local_domain?(domain)
      domain.blank? ||
        domain.casecmp?(Rails.configuration.x.local_domain) ||
        domain.casecmp?(Rails.configuration.x.web_domain)
    end
  end
end
