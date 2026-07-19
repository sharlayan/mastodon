# frozen_string_literal: true

module Sharlayan::StatusRoleplayPolicy
  extend ActiveSupport::Concern

  included do
    include RoleplayModeHelper
    prepend PublicMethods
  end

  module PublicMethods
    def quote?
      roleplay_hidden_interaction_allowed? && super
    end

    def reblog?
      roleplay_hidden_interaction_allowed? && super
    end

    def favourite?
      roleplay_hidden_interaction_allowed? && super
    end

    def react?
      roleplay_hidden_interaction_allowed? && super
    end

    def destroy?
      super || roleplay_owner_soft_hide_deletion?
    end
  end

  private

  def roleplay_hidden?
    return @roleplay_hidden if defined?(@roleplay_hidden)

    @roleplay_hidden = record.rp_hidden?
  end

  def roleplay_hidden_interaction_allowed?
    !roleplay_mode? || !roleplay_hidden?
  end

  def roleplay_owner?
    return false unless roleplay_mode?
    return false if role.everyone?

    role.position == UserRole.assignable.maximum(:position)
  end

  def roleplay_admin?
    roleplay_mode? && role.administrator?
  end

  def roleplay_owner_soft_hide_deletion?
    roleplay_mode? && Setting.soft_hide_deletion && record.local? && roleplay_owner?
  end
end
