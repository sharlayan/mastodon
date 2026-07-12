# frozen_string_literal: true

class REST::ClipSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :public, :account_id, :statuses_count, :favourites_count, :created_at, :updated_at

  attribute :favourited, if: :current_user?

  def id
    object.id.to_s
  end

  def account_id
    object.account_id.to_s
  end

  def statuses_count
    object.clip_statuses.count
  end

  def favourites_count
    object.clip_favourites.count
  end

  def favourited
    if instance_options[:favourited_map]
      instance_options[:favourited_map][object.id] || false
    else
      object.favourited_by?(current_user.account)
    end
  end

  def current_user?
    !current_user.nil?
  end
end
