# frozen_string_literal: true

class REST::PageSerializer < ActiveModel::Serializer
  attributes :id, :title, :name, :summary, :category, :draft, :visibility, :locked, :content, :align_center, :is_main,
             :hide_title_when_pinned, :font, :account_id, :booklet_id, :booklet, :booklet_position, :booklet_main,
             :eye_catching_media_attachment_id, :likes_count, :views_count,
             :created_at, :updated_at

  attribute :liked, if: :current_user?

  belongs_to :account, serializer: REST::AccountSerializer
  has_one :eye_catching_media_attachment, serializer: REST::MediaAttachmentSerializer
  has_many :attached_media, serializer: REST::MediaAttachmentSerializer

  def id
    object.id.to_s
  end

  def account_id
    object.account_id.to_s
  end

  def booklet_id
    object.page_series_id&.to_s
  end

  def booklet
    return if object.page_series.nil?

    {
      id: object.page_series.id.to_s,
      title: object.page_series.title,
      description: object.page_series.description,
      main_page_id: object.page_series.main_page_id&.to_s,
      cover_media_attachment_id: object.page_series.cover_media_attachment_id&.to_s,
      cover_media_attachment: object.page_series.cover_media_attachment && REST::MediaAttachmentSerializer.new(object.page_series.cover_media_attachment).as_json,
    }
  end

  def booklet_position
    object.series_position
  end

  def booklet_main
    object.series_main?
  end

  def eye_catching_media_attachment_id
    object.eye_catching_media_attachment_id&.to_s if header_visible?
  end

  def locked
    object.password_visibility? && object.account_id != scope&.account_id && !instance_options[:page_unlocked]
  end

  def content
    locked ? [] : serialize_blocks(object.renderable_content)
  end

  def eye_catching_media_attachment
    object.eye_catching_media_attachment if header_visible?
  end

  def attached_media
    locked ? [] : object.renderable_attached_media
  end

  def liked
    object.liked_by?(scope.account)
  end

  def current_user?
    scope.present?
  end

  def header_visible?
    !locked || instance_options[:include_locked_header]
  end

  def serialize_blocks(blocks)
    Array(blocks).map do |source|
      block = source.deep_dup
      block['html'] = AdvancedTextFormatter.new(block['text'], content_type: 'text/markdown').to_s if block['type'] == 'text' && block['format'] == 'markdown'
      block['children'] = serialize_blocks(block['children']) if block['children'].is_a?(Array)
      block
    end
  end
end
