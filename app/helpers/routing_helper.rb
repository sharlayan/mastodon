# frozen_string_literal: true

require 'request_store'

module RoutingHelper
  extend ActiveSupport::Concern

  include ActionView::Helpers::AssetTagHelper
  include Vite::TagsHelper

  included do
    include Rails.application.routes.url_helpers

    def default_url_options
      ActionMailer::Base.default_url_options
    end
  end

  def full_asset_url(source, **)
    source = ActionController::Base.helpers.asset_url(source, **) unless use_storage?

    URI.join(asset_host_uri, source).to_s
  end

  def full_media_attachment_url(attachment, style = :original, include_filename: true)
    source = if attachment.drive_pointer?
               drive_media_url(attachment.drive_access_key, style)
             else
               attachment.file.url(style, include_filename)
             end

    full_asset_url(source)
  end

  def full_media_attachment_preview_url(attachment)
    if attachment.drive_pointer?
      full_media_attachment_url(attachment, :small)
    elsif attachment.thumbnail.present?
      full_asset_url(attachment.thumbnail.url(:original))
    elsif attachment.file.styles.key?(:small)
      full_asset_url(attachment.file.url(:small))
    end
  end

  def expiring_asset_url(attachment, expires_in)
    case Paperclip::Attachment.default_options[:storage]
    when :s3, :azure
      attachment.expiring_url(expires_in.to_i)
    when :fog
      if Paperclip::Attachment.default_options.dig(:fog_credentials, :openstack_temp_url_key).present?
        attachment.expiring_url(expires_in.from_now)
      else
        full_asset_url(attachment.url)
      end
    when :filesystem
      full_asset_url(attachment.url)
    end
  end

  def asset_host
    return Rails.configuration.action_controller.asset_host || root_url unless RequestStore.active?

    RequestStore.store[:routing_helper_asset_host] ||= Rails.configuration.action_controller.asset_host || root_url
  end

  def asset_host_uri
    return URI.parse(asset_host) unless RequestStore.active?

    RequestStore.store[:routing_helper_asset_host_uri] ||= URI.parse(asset_host)
  end

  def frontend_asset_path(source, **)
    vite_asset_path(source, **)
  end

  def frontend_asset_url(source, **)
    full_asset_url(frontend_asset_path(source, **))
  end

  def use_storage?
    Rails.configuration.x.use_s3 || Rails.configuration.x.use_swift
  end
end
