# frozen_string_literal: true

class REST::PageSerializer < ActiveModel::Serializer
  attributes :id, :title, :name, :summary, :category, :draft, :content, :align_center,
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
    object.eye_catching_media_attachment_id&.to_s
  end

  def liked
    object.liked_by?(current_user.account)
  end

  def current_user?
    current_user.present?
  end
end
