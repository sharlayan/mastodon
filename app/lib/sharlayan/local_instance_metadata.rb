# frozen_string_literal: true

class Sharlayan::LocalInstanceMetadata
  include RoutingHelper
  include InstanceHelper

  SOFTWARE = 'mastodon'

  class << self
    def to_h
      return new.to_h unless RequestStore.active?

      RequestStore.store[:sharlayan_local_instance_metadata] ||= new.to_h
    end
  end

  def to_h
    {
      domain: instance_presenter.domain,
      instance_name: instance_presenter.title,
      software: SOFTWARE,
      version: instance_presenter.version,
      theme_color: ManifestSerializer::THEME_COLOR,
      favicon_url: favicon_url,
    }
  end

  private

  def favicon_url
    size = SiteUpload::ANDROID_ICON_SIZES.max

    app_icon_path(size).presence || frontend_asset_path("icons/android-chrome-#{size}x#{size}.png")
  end
end
