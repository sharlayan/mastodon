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

    def unreblog?
      owned?
    end
  end

  private

  def roleplay_hidden_show?
    return @roleplay_hidden_show if defined?(@roleplay_hidden_show)

    @roleplay_hidden_show = roleplay_owner? if roleplay_mode? && roleplay_hidden?
  end

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

  def roleplay_owner_soft_hide_deletion?
    Sharlayan::SoftHide.enabled? && record.local? && roleplay_owner?
  end
end
