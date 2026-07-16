# frozen_string_literal: true

class Admin::PagePolicy < ApplicationPolicy
  def destroy?
    role.can?(:manage_reports)
  end
end
