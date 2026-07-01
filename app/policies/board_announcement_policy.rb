# frozen_string_literal: true

class BoardAnnouncementPolicy < ApplicationPolicy
  def index?
    role.can?(:manage_announcements)
  end

  def create?
    role.can?(:manage_announcements)
  end

  def update?
    role.can?(:manage_announcements)
  end

  def destroy?
    role.can?(:administrator)
  end
end
