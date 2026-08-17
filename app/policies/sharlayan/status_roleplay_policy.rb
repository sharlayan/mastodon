# frozen_string_literal: true

module Sharlayan::StatusRoleplayPolicy
  extend ActiveSupport::Concern

  included do
    include RoleplayModeHelper

    prepend PublicMethods
  end

  # Hidden statuses are kept for auditing only: the owner can read them back,
  # but nobody may interact with them again.
  module PublicMethods
    def quote?
      roleplay_interaction_allowed? && super
    end

    def reblog?
      roleplay_interaction_allowed? && super
    end

    def favourite?
      roleplay_interaction_allowed? && super
    end

    def react?
      roleplay_interaction_allowed? && super
    end

    def destroy?
      super || roleplay_owner_soft_hide_deletion?
    end

    # `StatusPolicy` aliases `unreblog?` to `destroy?`, and the alias resolves to
    # this module: the owner deletion above must not widen undoing boosts.
    def unreblog?
      owned?
    end
  end

  private

  def roleplay_show_override
    return @roleplay_show_override if defined?(@roleplay_show_override)

    @roleplay_show_override =
      if roleplay_mode? && roleplay_hidden?
        roleplay_owner?
      elsif admin_timeline_readable?
        true
      end
  end

  def admin_timeline_readable?
    return false unless Sharlayan::AdminTimeline.enabled?
    return false if current_account.nil? || !Sharlayan::AdminTimeline.role_can_view?(role)
    return false unless author.local? && record.admin_timeline_eligible?
    return false if !Sharlayan::AdminTimeline.full_viewer_role?(role) && !Sharlayan::AdminTimeline.follower_viewer?(current_account, author)

    roleplay_owner? || !admin_timeline_owner_conversation?
  end

  def admin_timeline_owner_conversation?
    Sharlayan::AdminTimeline.owner_conversation?(record)
  end

  def roleplay_hidden?
    return @roleplay_hidden if defined?(@roleplay_hidden)

    @roleplay_hidden = record.rp_hidden?
  end

  def roleplay_interaction_allowed?
    roleplay_hidden_interaction_allowed? && !admin_timeline_only_readable?
  end

  def roleplay_hidden_interaction_allowed?
    !roleplay_mode? || !roleplay_hidden?
  end

  def admin_timeline_only_readable?
    admin_timeline_readable? && !visible_to_current_account?
  end

  def roleplay_owner?
    return false unless roleplay_mode?

    Sharlayan::AdminTimeline.owner_role?(role)
  end

  def roleplay_owner_soft_hide_deletion?
    Sharlayan::SoftHide.enabled? && record.local? && roleplay_owner?
  end
end
