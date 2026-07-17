# frozen_string_literal: true

module Sharlayan::InitialStateRoleplay
  extend ActiveSupport::Concern

  def apply_sharlayan_roleplay_meta!(store)
    roleplay_mode = RoleplayModeHelper.roleplay_mode?

    store[:roleplay_mode] = roleplay_mode
    store[:antenna_enabled] = false if roleplay_mode

    return store unless roleplay_mode && object.current_account

    store[:mfm_enabled] = true if Setting['force_mfm_enabled']
    store[:show_avatar_decorations] = true if Setting['force_avatar_decorations']
    store[:force_round_avatar] = Setting['force_round_avatar']
    store[:admin_timeline_owner_viewer] = admin_timeline_owner_viewer?
    store[:soft_hide_deletion] = Setting['soft_hide_deletion']
    store
  end

  private

  def admin_timeline_owner_viewer?
    role = object_account_user&.role
    return false if role.nil? || role.everyone?

    top_position = UserRole.assignable.maximum(:position)
    role.position == top_position
  end
end
