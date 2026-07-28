# frozen_string_literal: true

class REST::PageSerializer < ActiveModel::Serializer
  attributes :id, :title, :name, :summary, :category, :draft, :visibility, :locked, :content, :align_center, :is_main,
             :hide_title_when_pinned, :font, :account_id,
             :eye_catching_media_attachment_id, :likes_count,
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

  def eye_catching_media_attachment_id
    object.eye_catching_media_attachment_id&.to_s if header_visible?
  end

  def locked
    object.password_visibility? && object.account_id != scope&.account_id && !instance_options[:page_unlocked]
  end

  def content
    locked ? [] : object.renderable_content
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
end
