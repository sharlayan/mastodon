# frozen_string_literal: true

class REST::BoardAnnouncementAttachmentSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :id, :type, :url, :preview_url, :file_name,
             :content_type, :size, :blurhash, :meta

  def id
    object.id.to_s
  end

  def url
    full_asset_url(object.file.url(:original))
  end

  def preview_url
    if object.image? && object.file.styles.key?(:small)
      full_asset_url(object.file.url(:small))
    else
      url
    end
  end

  def file_name
    object.file_file_name
  end

  def content_type
    object.file_content_type
  end

  def size
    object.file_file_size
  end

  def meta
    object.file_meta
  end
end
