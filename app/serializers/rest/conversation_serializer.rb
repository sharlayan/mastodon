# frozen_string_literal: true

class REST::ConversationSerializer < ActiveModel::Serializer
  attributes :id, :unread

  has_many :participant_accounts, key: :accounts, serializer: REST::AccountSerializer
  has_one :last_status, serializer: REST::StatusSerializer

  attribute :member_ids, if: :grouped?

  def id
    object.id.to_s
  end

  def unread
    object.group_unread.nil? ? object.unread : object.group_unread
  end

  def member_ids
    object.member_ids.map(&:to_s)
  end

  def grouped?
    object.member_ids.present?
  end
end
