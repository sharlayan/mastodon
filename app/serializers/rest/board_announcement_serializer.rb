# frozen_string_literal: true

class REST::BoardAnnouncementSerializer < ActiveModel::Serializer
  attributes :id, :title, :content, :published_at, :updated_at

  attribute :read, if: :current_user?

  has_many :attachments, serializer: REST::BoardAnnouncementAttachmentSerializer

  def current_user?
    !current_user.nil?
  end

  def id
    object.id.to_s
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
end
