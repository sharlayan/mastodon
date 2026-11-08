# frozen_string_literal: true

class ChatConversationPolicy < ApplicationPolicy
  def index?
    manage_access? || audit_access?
  end

  def show?
    manage_access? || (audit_access? && between_local_accounts?)
  end

  def destroy?
    manage_access?
  end

  def list_all?
    manage_access?
  end

  private

  def manage_access?
    role.can?(:manage_users)
  end

  def audit_access?
    RoleplayModeHelper.roleplay_mode? && role.can_extra?(:view_admin_timeline)
  end

  def between_local_accounts?
    record.local? && record.accounts.none?(&:remote?)
  end
end
