# frozen_string_literal: true

module MisskeyCompat
  class EmojisController < ApplicationController
    include RoutingHelper

    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    NAME_PATTERN = /\A[a-zA-Z0-9\-_@.]+\z/

    def show
      name = params[:name].to_s.sub(/\.(webp|png)\z/i, '')

      return not_found unless name.match?(NAME_PATTERN)

      shortcode, host, extra = name.split('@')

      return bad_request if extra.present?
      return not_found if shortcode.blank?

      emoji = CustomEmoji.enabled.find_by(shortcode: shortcode, domain: local_host?(host) ? nil : host)

      return not_found if emoji.nil?

      expires_in 1.day, public: true
      redirect_to full_asset_url(emoji.image.url(style_for_request)), allow_other_host: true, status: 302
    end

    private

    def local_host?(host)
      host.blank? || host == '.'
    end

    def style_for_request
      params.key?(:static) || params.key?(:badge) ? :static : :original
    end

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end
  end
end
