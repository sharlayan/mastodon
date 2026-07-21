# frozen_string_literal: true

module MisskeyCompat
  class MediaProxyController < ApplicationController
    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    def show
      url = params[:url].to_s
      parsed = Addressable::URI.parse(url) if url.present?

      return not_found if parsed.nil? || !%w(http https).include?(parsed.scheme) || parsed.host.blank?
      return not_found unless known_url?(parsed.to_s)

      expires_in 1.day, public: true
      redirect_to parsed.to_s, allow_other_host: true, status: 302
    rescue Addressable::URI::InvalidURIError
      not_found
    end

    private

    def known_url?(url)
      PreviewCard.exists?(url: url) ||
        MediaAttachment.where(remote_url: url).or(MediaAttachment.where(thumbnail_remote_url: url)).exists?
    end

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end
  end
end
