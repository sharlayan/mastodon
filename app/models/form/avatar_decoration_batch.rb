# frozen_string_literal: true

class Form::AvatarDecorationBatch < Form::BaseBatch
  attr_accessor :avatar_decoration_ids

  def save
    case action
    when 'approve'
      approve!
    when 'delete'
      delete!
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
