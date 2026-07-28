# frozen_string_literal: true

module MisskeyCompat
  class MediaProxyController < ApplicationController
    MAX_URL_BYTES = 8.kilobytes
    NEGATIVE_CACHE_TTL = 30.seconds

    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    def show
      url = params[:url].to_s
      return not_found if url.bytesize > MAX_URL_BYTES

      parsed = Addressable::URI.parse(url) if url.present?

      return not_found if parsed.nil? || !%w(http https).include?(parsed.scheme) || parsed.host.blank?
      return not_found unless known_url?(parsed)

      expires_in 1.day, public: true
      redirect_to parsed.to_s, allow_other_host: true, status: 302
    rescue Addressable::URI::InvalidURIError
      not_found
    end

    private

    def known_url?(uri)
      url = uri.to_s
      cache_key = "misskey_media_proxy:missing:#{Digest::SHA256.hexdigest(url)}"
      return false if Rails.cache.read(cache_key)

      known = PreviewCard.exists?(url: url) ||
              MediaAttachment.exists?(["(remote_url <> '' AND remote_url = :url) OR thumbnail_remote_url = :url", { url: url }]) ||
              known_custom_emoji?(uri) ||
              known_instance_favicon?(uri)

      Rails.cache.write(cache_key, true, expires_in: NEGATIVE_CACHE_TTL) unless known
      known
    end

    def known_custom_emoji?(uri)
      url = uri.to_s

      return true if CustomEmoji.exists?(image_remote_url: url)

      emoji = custom_emoji_from_asset_path(uri.path)
      emoji.present? && [emoji.image.url, emoji.image.url(:static)].any? { |candidate| helpers.full_asset_url(candidate) == url }
    end

    def custom_emoji_from_asset_path(path)
      id_partition = path[%r{/custom_emojis/images/((?:\d{3}/)+)}, 1]
      return nil if id_partition.blank?

      CustomEmoji.find_by(id: id_partition.delete('/').to_i)
    end

    def known_instance_favicon?(uri)
      return true if InstanceMetadata.exists?(favicon_url: uri.to_s)
      return true if known_local_instance_favicon?(uri)
      return false unless uri.scheme == 'https' && uri.path == '/favicon.ico' && uri.query.blank? && uri.fragment.blank?

      Account.remote.exists?(domain: uri.host)
    end

    def known_local_instance_favicon?(uri)
      return false if uri.query.present? || uri.fragment.present?

      metadata = InstanceMetadata.find_by(favicon_url: uri.path)
      metadata.present? && helpers.full_asset_url(metadata.favicon_url) == uri.to_s
    end

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end
  end
end
