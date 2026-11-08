# frozen_string_literal: true

class REST::ChatInvitationSerializer < ActiveModel::Serializer
  attributes :id, :state, :created_at
  belongs_to :chat_conversation, key: :conversation, serializer: REST::ChatConversationSerializer
  belongs_to :inviter_account, key: :inviter, serializer: REST::AccountSerializer
  belongs_to :invitee_account, key: :invitee, serializer: REST::AccountSerializer

  def id
    object.id.to_s
  end
end
