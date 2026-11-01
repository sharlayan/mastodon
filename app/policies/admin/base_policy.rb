# frozen_string_literal: true

class Admin::BasePolicy < ApplicationPolicy
  def access?
    role.administrator? || role.can?(*UserRole::Flags::CATEGORIES.fetch_values(:moderation, :administration, :devops).flatten) || roleplay_management_timeline?
  end

  private

  def roleplay_management_timeline?
    RoleplayModeHelper.roleplay_mode? && role.can_extra?(:view_admin_timeline)
  end
end
