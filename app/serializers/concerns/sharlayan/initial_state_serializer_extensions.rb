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
    store
  end

  private

  def default_meta_store
    super.merge(
      force_local_only: Setting.force_local_only,
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      antenna_enabled: Setting.antenna_enabled,
      drive_enabled: Setting.drive_enabled,
      board_announcements_enabled: Setting.board_announcements_enabled,
      avatar_decorations_enabled: Setting.avatar_decorations_enabled,
      avatar_decorations_federation_enabled: Setting.avatar_decorations_federation_enabled,
      cat_enabled: Setting.cat_enabled,
      cat_federation_enabled: Setting.cat_federation_enabled,
      local_account_statuses_access: Setting.local_account_statuses_access,
      local_status_page_access: Setting.local_status_page_access,
      roleplay_mode: RoleplayModeHelper.roleplay_mode?
    )
  end

  def signed_in_meta
    {
      visible_reactions: object_account_user.setting_visible_reactions,
      show_instance_info: object_account_user.settings.as_json.fetch(:'web.show_instance_info', false),
      custom_emoji_size: object_account_user.settings_custom_emoji_size,
      reaction_custom_emoji_size: object_account_user.settings_reaction_custom_emoji_size,
      reaction_local_emoji_only: Setting.reaction_local_emoji_only,
      reactions_enabled: Setting.reactions_enabled,
      mfm_enabled: object_account_user.settings_mfm_enabled,
      mfm_animations: object_account_user.settings_mfm_animations,
      mfm_fold_mode: object_account_user.settings_mfm_fold_mode,
      mfm_allow_composition: Setting.mfm_allow_composition,
      show_avatar_decorations: object_account_user.settings['avatar_decorations.show'],
      show_federated_avatar_decorations: object_account_user.settings['avatar_decorations.show_federated'],
      show_cat: object_account_user.settings['cat.show'],
      show_federated_cat: object_account_user.settings['cat.show_federated'],
      avatar_decoration_shape: object_account_user.settings['avatar_decorations.shape'],
      color_scheme: object_account_user.settings['web.color_scheme'],
      contrast: object_account_user.settings['web.contrast'],
      custom_emoji_mute_hidden: object_account_user.settings['web.custom_emoji_mute_hidden'],
      ignore_others_pages_view: object_account_user.settings['web.ignore_others_pages_view'],
      custom_emoji_mutes: object.current_account.custom_emoji_mutes.order(id: :desc).map { |mute| { id: mute.id.to_s, prefix: mute.prefix, domain: mute.domain, reject_reactions: mute.reject_reactions, hide_in_picker: mute.hide_in_picker } },
      reaction_mutes: object.current_account.reaction_mutes.includes(:target_account).order(id: :desc).map { |mute| { id: mute.id.to_s, target_account_id: mute.target_account_id&.to_s, target_acct: mute.target_account&.acct, target_domain: mute.target_domain } },
    }
  end
end
