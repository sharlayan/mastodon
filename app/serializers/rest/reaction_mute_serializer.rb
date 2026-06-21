# frozen_string_literal: true

class REST::ReactionMuteSerializer < ActiveModel::Serializer
  attributes :id, :target_account_id, :target_domain, :created_at

  def id
    object.id.to_s
  end

  def target_account_id
    object.target_account_id&.to_s
  end
end
