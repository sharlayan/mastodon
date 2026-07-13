# frozen_string_literal: true

class REST::MediaAttachmentSerializer < ActiveModel::Serializer
  include RoutingHelper
  include RoleplayModeHelper

  # Please update `app/javascript/mastodon/api_types/media_attachments.ts` when making changes to the attributes

  attributes :id, :type, :url, :preview_url,
             :remote_url, :preview_remote_url, :text_url, :meta,
             :description, :blurhash

  def id
    object.id.to_s
  end

  def url
    if object.not_processed?
      nil
    elsif rp_hidden_media?
      medium_url(object.id)
    elsif object.needs_redownload? || object.discarded?
      media_proxy_url(object.id, :original)
    else
      full_asset_url(object.file.url(:original))
    end
  end

  def remote_url
    object.remote_url.presence
  end

  def preview_url
    if rp_hidden_media?
      medium_url(object.id)
    elsif object.needs_redownload? || object.discarded?
      media_proxy_url(object.id, :small)
    elsif object.thumbnail.present?
      full_asset_url(object.thumbnail.url(:original))
    elsif object.file.styles.key?(:small)
      full_asset_url(object.file.url(:small))
    end
  end

  def preview_remote_url
    object.thumbnail_remote_url.presence
  end

  def text_url
    object.local? && object.shortcode.present? ? medium_url(object) : nil
  end

  def meta
    object.file.meta
  end

  private

  def rp_hidden_media?
    return false unless instance_options[:rp_admin] || (!roleplay_mode? && Setting.soft_hide_deletion)

    object.status_id.present? && RpHiddenStatus.exists?(status_id: object.status_id)
  end
end
