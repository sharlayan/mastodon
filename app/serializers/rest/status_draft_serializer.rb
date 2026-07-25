# frozen_string_literal: true

class REST::StatusDraftSerializer < ActiveModel::Serializer
  attributes :id, :created_at, :updated_at, :params

  has_many :media_attachments, serializer: REST::MediaAttachmentSerializer

  def id
    object.id.to_s
  end

  def params
    object.data.merge('media_ids' => object.media_attachments.map { |media| media.id.to_s })
  end
end
