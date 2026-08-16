# frozen_string_literal: true

module Sharlayan::AdminSettingsExtensions
  extend ActiveSupport::Concern

  KEYS = %i(
    theme_color
    background_color
    background_opacity
    background_on_settings_pages
    force_local_only
    roleplay_disable_local_timeline
    roleplay_hide_public_timelines_from_admins
    norss
    soft_hide_deletion
    local_account_statuses_access
    local_status_page_access
    reaction_local_emoji_only
    reactions_enabled
    mfm_enabled
    mfm_allow_composition
    force_mfm_enabled
    force_avatar_decorations
    force_round_avatar
    roleplay_forced_skin
    circles_enabled
    clips_enabled
    auto_quote_from_url
    pages_enabled
    pages_drive_only
    rate_limit_bypass_enabled
    avatar_decorations_enabled
    avatar_decorations_federation_enabled
    avatar_decorations_local_only_view
    avatar_decorations_max_count
    cat_enabled
    cat_federation_enabled
    allow_user_custom_css
    board_announcements_enabled
    instance_metadata_enabled
    antenna_enabled
    federation_instance_edges_enabled
    federation_request_statistics_enabled
    misskey_compat_enabled
    misskey_compat_signin_flow_enabled
    misskey_compat_signin_flow_allowed_origins
    misskey_compat_expose_follow_graph
    online_status_enabled
    drive_enabled
    drive_quota
    drive_max_file_size
    drive_allowed_extensions
    status_character_limit
    profile_fields_limit
    remote_media_attachments_limit
    user_themes_enabled
    user_theme_catalog
    user_theme_defaults
  ).freeze

  INTEGER_KEYS = %i(
    avatar_decorations_max_count
    background_opacity
    drive_quota
    drive_max_file_size
    status_character_limit
    profile_fields_limit
    remote_media_attachments_limit
  ).freeze

  BOOLEAN_KEYS = %i(
    background_on_settings_pages
    force_local_only
    roleplay_disable_local_timeline
    roleplay_hide_public_timelines_from_admins
    norss
    soft_hide_deletion
    reaction_local_emoji_only
    reactions_enabled
    mfm_enabled
    mfm_allow_composition
    force_mfm_enabled
    force_avatar_decorations
    force_round_avatar
    circles_enabled
    clips_enabled
    auto_quote_from_url
    pages_enabled
    pages_drive_only
    avatar_decorations_enabled
    avatar_decorations_federation_enabled
    avatar_decorations_local_only_view
    cat_enabled
    cat_federation_enabled
    rate_limit_bypass_enabled
    allow_user_custom_css
    board_announcements_enabled
    instance_metadata_enabled
    antenna_enabled
    federation_instance_edges_enabled
    federation_request_statistics_enabled
    misskey_compat_enabled
    misskey_compat_signin_flow_enabled
    misskey_compat_expose_follow_graph
    online_status_enabled
    drive_enabled
    user_themes_enabled
  ).freeze

  included do
    validates :local_account_statuses_access, inclusion: { in: Form::AdminSettings::FEED_ACCESS_MODES }, if: -> { defined?(@local_account_statuses_access) }
    validates :local_status_page_access, inclusion: { in: Form::AdminSettings::FEED_ACCESS_MODES }, if: -> { defined?(@local_status_page_access) }
    validates :drive_quota, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, if: -> { defined?(@drive_quota) }
    validates :drive_max_file_size, numericality: { only_integer: true, greater_than: 0 }, if: -> { defined?(@drive_max_file_size) }
    validates :status_character_limit, numericality: { only_integer: true, greater_than_or_equal_to: Sharlayan::SettingExtensions::MIN_STATUS_CHARACTER_LIMIT }, if: -> { defined?(@status_character_limit) }
    validates :profile_fields_limit, numericality: { only_integer: true, in: 0..ActivityPub::ProcessAccountService::MAX_PROFILE_FIELDS }, if: -> { defined?(@profile_fields_limit) }
    validates :remote_media_attachments_limit, numericality: { only_integer: true, in: Status::MEDIA_ATTACHMENTS_LIMIT..16 }, if: -> { defined?(@remote_media_attachments_limit) }
    validates :background_opacity, numericality: { only_integer: true, in: 0..100 }, if: -> { defined?(@background_opacity) }
    validates :theme_color, format: { with: /\A#(?:[0-9a-fA-F]{3}){1,2}\z/ }, if: -> { defined?(@theme_color) }
    validates :background_color, format: { with: /\A#(?:[0-9a-fA-F]{3}){1,2}\z/ }, allow_blank: true, if: -> { defined?(@background_color) }
    validates :user_theme_catalog, :user_theme_defaults, length: { maximum: 65_536 }, if: -> { defined?(@user_theme_catalog) || defined?(@user_theme_defaults) }
    validate :validate_drive_allowed_extensions, if: -> { defined?(@drive_allowed_extensions) }
    validate :validate_misskey_signin_origins, if: -> { defined?(@misskey_compat_signin_flow_allowed_origins) }
    validate :validate_roleplay_forced_skin, if: -> { defined?(@roleplay_forced_skin) }
  end

  private

  def validate_drive_allowed_extensions
    extensions = DriveFile.parse_extensions(@drive_allowed_extensions)
    rejected = extensions.grep_v(DriveFile::EXTENSION_PATTERN) + (extensions & DriveFile::FORBIDDEN_EXTENSIONS)

    errors.add(:drive_allowed_extensions, I18n.t('admin.settings.drive.allowed_extensions_invalid', extensions: rejected.uniq.join(', '))) if rejected.any?
  end

  def validate_misskey_signin_origins
    rejected = MisskeyCompat::SigninOriginPolicy.invalid_entries(@misskey_compat_signin_flow_allowed_origins)
    return if rejected.empty?

    errors.add(:misskey_compat_signin_flow_allowed_origins, I18n.t('admin.settings.misskey_compat.signin_flow_allowed_origins_invalid', origins: rejected.join(', ')))
  end

  def validate_roleplay_forced_skin
    return if @roleplay_forced_skin.blank? || Themes.instance.skins_for('glitch').include?(@roleplay_forced_skin)

    errors.add(:roleplay_forced_skin, :inclusion)
  end
end
