# frozen_string_literal: true

class REST::AvatarDecorationMuteSerializer < ActiveModel::Serializer
  attributes :id, :target_account_id, :target_domain

  def id
    object.id.to_s
  end

  def target_account_id
    object.target_account_id&.to_s
  end
end
