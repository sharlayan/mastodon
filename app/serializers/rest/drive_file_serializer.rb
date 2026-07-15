# frozen_string_literal: true

class REST::DriveFileSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :id, :type, :url, :preview_url, :meta,
             :description, :blurhash, :sensitive, :size,
             :content_type, :name, :file_name, :folder_id,
             :orphaned, :created_at

  def id
    object.id.to_s
  end

  def folder_id
    object.folder_id&.to_s
  end

  def url
    full_asset_url(object.file.url(:original))
  end

  def preview_url
    if object.thumbnail.present?
      full_asset_url(object.thumbnail.url(:original))
    elsif object.file.styles.key?(:small)
      full_asset_url(object.file.url(:small))
    else
      full_asset_url(object.file.url(:original))
    end
  end

  def meta
    object.file.meta
  end

  def size
    object.file_file_size
  end

  def content_type
    object.file_content_type
  end

  def name
    object.display_name
  end

  def file_name
    object.file_file_name
  end

  def orphaned
    attached_ids = instance_options[:attached_ids]
    return attached_ids.exclude?(object.id) if attached_ids

    !object.attached?
  end
end
