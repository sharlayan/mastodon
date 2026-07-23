# frozen_string_literal: true

class FavouriteClipService < BaseService
  def call(account, clip)
    raise Mastodon::NotPermittedError unless clip.visible_to?(account)

    account.clip_favourites.find_or_create_by!(clip: clip)
  rescue ActiveRecord::RecordNotUnique
    account.clip_favourites.find_by!(clip: clip)
  end
end
