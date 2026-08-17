# frozen_string_literal: true

module Sharlayan::InitialStateSerializerExtensions
  extend ActiveSupport::Concern

  prepended do
    attribute :max_reactions
  end

  def max_reactions
    StatusReactionValidator::LIMIT
  end

  def meta
    store = super
    store.merge!(signed_in_meta) if object.current_account
    apply_sharlayan_roleplay_meta!(store)
  end

  private

  def default_meta_store
    super.merge(
      force_local_only: Setting.force_local_only,
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      pages_drive_only: Setting.pages_drive_only,
      antenna_enabled: Setting.antenna_enabled,
      drive_enabled: Setting.drive_enabled,
      board_announcements_enabled: Setting.board_announcements_enabled,
      avatar_decorations_enabled: Setting.avatar_decorations_enabled,
      avatar_decorations_federation_enabled: Setting.avatar_decorations_federation_enabled,
      avatar_decorations_local_only_view: Setting.avatar_decorations_local_only_view,
      cat_enabled: Setting.cat_enabled,
      cat_federation_enabled: Setting.cat_federation_enabled,
      local_account_statuses_access: Setting.local_account_statuses_access,
      local_status_page_access: Setting.local_status_page_access,
      roleplay_mode: RoleplayModeHelper.roleplay_mode?,
      roleplay_disable_local_timeline: RoleplayModeHelper.roleplay_local_timeline_disabled?,
      user_themes_enabled: Setting.user_themes_enabled,
      user_theme_catalog: Setting.user_theme_catalog,
      user_theme_defaults: Setting.user_theme_defaults
    )
  end

  def signed_in_meta
    {
      federation_universe_enabled: Sharlayan::FederationEdgeAggregator.enabled?,
      visible_reactions: object_account_user.setting_visible_reactions,
      show_instance_info: object_account_user.settings.as_json.fetch(:'web.show_instance_info', false),
      custom_emoji_size: object_account_user.settings_custom_emoji_size,
      reaction_custom_emoji_size: object_account_user.settings_reaction_custom_emoji_size,
      reaction_local_emoji_only: Setting.reaction_local_emoji_only,
      reactions_enabled: Setting.reactions_enabled,
      mfm_enabled: mfm_enabled,
      mfm_animations: object_account_user.settings_mfm_animations,
      mfm_fold_mode: object_account_user.settings_mfm_fold_mode,
      mfm_allow_composition: Setting.mfm_allow_composition,
      show_avatar_decorations: show_avatar_decorations,
      show_federated_avatar_decorations: object_account_user.settings['avatar_decorations.show_federated'],
      show_cat: object_account_user.settings['cat.show'],
      show_cat_speak: object_account_user.settings['cat.show_speak'],
      show_federated_cat: object_account_user.settings['cat.show_federated'],
      avatar_decoration_shape: object_account_user.settings['avatar_decorations.shape'],
      force_round_avatar: RoleplayModeHelper.roleplay_mode? && Setting['force_round_avatar'],
      admin_timeline_owner_viewer: roleplay_owner_viewer?,
      soft_hide_deletion: Sharlayan::SoftHide.enabled?,
      color_scheme: object_account_user.settings['web.color_scheme'],
      contrast: object_account_user.settings['web.contrast'],
      custom_emoji_mute_hidden: object_account_user.settings['web.custom_emoji_mute_hidden'],
      ignore_others_pages_view: object_account_user.settings['web.ignore_others_pages_view'],
      inline_compose_tabs: inline_compose_tabs,
      user_theme: object_account_user.settings['web.user_theme'],
      use_my_archive: object_account_user.settings['web.use_my_archive'],
      custom_emoji_mutes: object.current_account.custom_emoji_mutes.order(id: :desc).map { |mute| { id: mute.id.to_s, prefix: mute.prefix, domain: mute.domain, reject_reactions: mute.reject_reactions, hide_in_picker: mute.hide_in_picker } },
      reaction_mutes: object.current_account.reaction_mutes.includes(:target_account).order(id: :desc).map { |mute| { id: mute.id.to_s, target_account_id: mute.target_account_id&.to_s, target_acct: mute.target_account&.acct, target_domain: mute.target_domain } },
    }
  end

  def show_avatar_decorations
    return true if RoleplayModeHelper.roleplay_mode? && Setting['force_avatar_decorations']

    object_account_user.settings['avatar_decorations.show']
  end

  def inline_compose_tabs
    value = JSON.parse(object_account_user.settings[:inline_compose_tabs])
    Sharlayan::InlineComposeTabs.normalize(value)
  rescue JSON::ParserError, TypeError, Mastodon::InvalidParameterError
    []
  end

  def mfm_enabled
    return true if RoleplayModeHelper.roleplay_mode? && Setting['force_mfm_enabled']

    object_account_user.settings_mfm_enabled
  end

  def roleplay_owner_viewer?
    return false unless RoleplayModeHelper.roleplay_mode?

    role = object_account_user.role
    role.present? && !role.everyone? && role.position == UserRole.assignable.maximum(:position)
  end
end
