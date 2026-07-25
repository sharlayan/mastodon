# frozen_string_literal: true

class UnfavouriteClipService < BaseService
  def call(account, clip)
    account.clip_favourites.where(clip: clip).destroy_all
  end
end
