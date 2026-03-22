# frozen_string_literal: true

class REST::AccountSwitchAuthorizationSerializer < ActiveModel::Serializer
  attributes :id, :created_at

  belongs_to :target_account, serializer: REST::AccountSerializer

  def id
    object.id.to_s
  end
end
