# frozen_string_literal: true

module MisskeyCompat
  class URLPreviewController < ApplicationController
    include RoutingHelper

    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    def show
      url = params[:url]
      return render json: {}, status: 400 unless url.is_a?(String) && url.present?

      card = find_card(url)
      return render_preview_failed if card.nil?

      expires_in 1.hour, public: true
      render json: summaly(card)
    end

    private

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
    end

    def render_preview_failed
      render json: { error: { message: 'Failed to get preview', code: 'URL_PREVIEW_FAILED', id: '09d01cb5-53b9-4856-82e5-38a50c290a3b', kind: 'client' } }, status: 422
    end

    def find_card(url)
      PreviewCard.find_by(url: url) ||
        PreviewCardsStatus.where(url: url).order(status_id: :desc).first&.preview_card
    end

    def summaly(card)
      {
        url: card.url,
        title: card.title.presence,
        icon: nil,
        description: card.description.presence,
        thumbnail: card.image? ? full_asset_url(card.image.url(:original)) : nil,
        sitename: card.provider_name.presence,
        sensitive: false,
        activityPub: nil,
        player: player_for(card),
      }
    end

    def player_for(card)
      embeddable = card.video? && card.embed_url.present?

      {
        url: embeddable ? card.embed_url : nil,
        width: embeddable ? card.width : nil,
        height: embeddable ? card.height : nil,
        allow: [],
      }
    end
  end
end
