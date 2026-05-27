# frozen_string_literal: true

class Form::AvatarDecorationBatch < Form::BaseBatch
  attr_accessor :avatar_decoration_ids, :category_id, :category_name

  def save
    case action
    when 'approve'
      approve!
    when 'delete'
      delete!
    when 'update'
      update!
    end
  end

  private

  def avatar_decorations
    @avatar_decorations ||= AvatarDecoration.where(id: avatar_decoration_ids)
  end

  def approve!
    verify_authorization(:update?)

    ApplicationRecord.transaction do
      avatar_decorations.each do |decoration|
        decoration.update!(approved: true)
        log_action :update, decoration
      end
    end
  end

  def update!
    verify_authorization(:update?)

    category = if category_id.present?
                 AvatarDecorationCategory.find(category_id)
               elsif category_name.present?
                 AvatarDecorationCategory.find_or_create_by!(name: category_name.strip)
               end

    avatar_decorations.each do |decoration|
      decoration.update(category_id: category&.id)
      log_action :update, decoration
    end
  end

  def delete!
    verify_authorization(:destroy?)

    ApplicationRecord.transaction do
      avatar_decorations.each do |decoration|
        decoration.destroy!
        log_action :destroy, decoration
      end
    end
  end

  def verify_authorization(permission)
    avatar_decorations.each { |decoration| authorize(decoration, permission) }
  end
end
