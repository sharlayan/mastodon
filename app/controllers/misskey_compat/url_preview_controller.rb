# frozen_string_literal: true

module MisskeyCompat
  class URLPreviewController < ApplicationController
    include RoutingHelper

    skip_before_action :require_functional!

    before_action :require_misskey_compat_enabled!

    def show
      url = params[:url].to_s
      return render json: {}, status: 400 if url.blank?

      card = find_card(url)
      return head 204 if card.nil?

      expires_in 1.hour, public: true
      render json: summaly(card)
    end

    private

    def require_misskey_compat_enabled!
      not_found unless Setting.misskey_compat_enabled
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
