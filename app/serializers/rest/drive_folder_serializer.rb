# frozen_string_literal: true

class REST::DriveFolderSerializer < ActiveModel::Serializer
  attributes :id, :name, :parent_id, :created_at

  attribute :files_count, if: :detail?
  attribute :folders_count, if: :detail?

  def id
    object.id.to_s
  end

  def parent_id
    object.parent_id&.to_s
  end

  def files_count
    object.files_count
  end

  def folders_count
    object.folders_count
  end

  def detail?
    instance_options[:detail].present?
  end
end
