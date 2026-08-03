# frozen_string_literal: true

class REST::PageSeriesSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :displayed, :account_id, :main_page_id, :main_page_name, :cover_media_attachment_id, :pages_count, :created_at, :updated_at

  belongs_to :account, serializer: REST::AccountSerializer
  has_one :cover_media_attachment, serializer: REST::MediaAttachmentSerializer

  def id
    object.id.to_s
  end

  def main_page_id
    object.main_page_id&.to_s
  end

  def account_id
    object.account_id.to_s
  end

  def main_page_name
    object.main_page&.name
  end

  def cover_media_attachment_id
    object.cover_media_attachment_id&.to_s
  end

  def pages_count
    object.pages.size
  end
end
