# frozen_string_literal: true

class ChatConversationPolicy < ApplicationPolicy
  def index?
    moderation_access?
  end

  def show?
    moderation_access? && local_conversation?
  end

  def destroy?
    role.can?(:manage_users)
  end

  private

  def moderation_access?
    role.can?(:manage_users) || (RoleplayModeHelper.roleplay_mode? && role.can_extra?(:view_admin_timeline))
  end

  def local_conversation?
    record.accounts.all?(&:local?)
  end
end
