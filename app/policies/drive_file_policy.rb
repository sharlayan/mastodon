# frozen_string_literal: true

class DriveFilePolicy < ApplicationPolicy
  def index?
    role.can?(:manage_users)
  end

  def destroy?
    role.can?(:manage_users)
  end
end
