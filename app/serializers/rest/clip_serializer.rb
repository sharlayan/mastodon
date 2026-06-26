# frozen_string_literal: true

class REST::ClipSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :public, :account_id, :statuses_count, :created_at, :updated_at

  def id
    object.id.to_s
  end

  def account_id
    object.account_id.to_s
  end

  def statuses_count
    object.clip_statuses.count
  end
end
