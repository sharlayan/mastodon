# frozen_string_literal: true

class REST::PageSeriesSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :main_page_id, :cover_media_attachment_id, :pages_count, :created_at, :updated_at

  has_one :cover_media_attachment, serializer: REST::MediaAttachmentSerializer

  def id
    object.id.to_s
  end

  def main_page_id
    object.main_page_id&.to_s
  end

  def cover_media_attachment_id
    object.cover_media_attachment_id&.to_s
  end

  def pages_count
    object.pages.size
  end
end
