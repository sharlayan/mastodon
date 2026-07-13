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
    relationships ? relationships.statuses_count_map.fetch(object.id, 0) : object.clip_statuses.count
  end

  def favourites_count
    relationships ? relationships.favourites_count_map.fetch(object.id, 0) : object.clip_favourites.count
  end

  def favourited
    if relationships
      relationships.favourited_map[object.id] || false
    elsif instance_options[:favourited_map]
      instance_options[:favourited_map][object.id] || false
    else
      object.favourited_by?(current_user.account)
    end
  end

  def current_user?
    !current_user.nil?
  end

  def relationships
    instance_options[:relationships]
  end
end
