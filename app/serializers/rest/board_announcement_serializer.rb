# frozen_string_literal: true

class REST::BoardAnnouncementSerializer < ActiveModel::Serializer
  attributes :id, :title, :content, :icon, :display, :need_confirmation_to_read, :silence, :published_at, :updated_at

  attribute :read, if: :current_user?

  has_many :attachments, serializer: REST::BoardAnnouncementAttachmentSerializer
  has_many :reactions, serializer: REST::AnnouncementReactionSerializer
  has_many :emojis, serializer: REST::CustomEmojiSerializer

  def current_user?
    !current_user.nil?
  end

  def id
    object.id.to_s
  end

  def reactions
    if relationships
      relationships.reaction_groups_map[object.id] || []
    else
      object.reactions(current_user&.account)
    end
  end

  def content
    object.text_html
  end

  def read
    if object.respond_to?(:read_by_current_user)
      object.read_by_current_user
    else
      object.read?(current_user.account)
    end
  end

  def relationships
    instance_options[:relationships]
  end
end
