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
    store
  end
end
