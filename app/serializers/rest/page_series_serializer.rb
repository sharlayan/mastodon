# frozen_string_literal: true

class REST::PageSeriesSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :displayed, :account_id, :main_page_id, :main_page_name, :entry_page_id, :entry_page_name,
             :cover_media_attachment_id, :pages_count, :created_at, :updated_at

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

  def entry_page_id
    entry_page&.id&.to_s
  end

  def entry_page_name
    entry_page&.name
  end

  def cover_media_attachment_id
    object.cover_media_attachment_id&.to_s
  end

  def pages_count
    object.pages.size
  end

  private

  def entry_page
    return @entry_page if defined?(@entry_page)

    @entry_page = object.entry_page(preloaded_pages: object.pages)
  end
end
