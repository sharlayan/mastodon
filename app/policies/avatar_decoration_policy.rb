# frozen_string_literal: true

class AvatarDecorationPolicy < ApplicationPolicy
  def index?
    role.can?(:manage_custom_emojis)
  end

  def create?
    role.can?(:manage_custom_emojis)
  end

  def update?
    role.can?(:manage_custom_emojis)
  end

  def destroy?
    role.can?(:manage_custom_emojis)
  end
end
