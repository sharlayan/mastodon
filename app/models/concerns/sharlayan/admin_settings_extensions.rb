# frozen_string_literal: true

module Sharlayan::AdminSettingsExtensions
  extend ActiveSupport::Concern

  KEYS = %i(
    theme_color
    force_local_only
    local_account_statuses_access
    local_status_page_access
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
    rate_limit_bypass_enabled
    avatar_decorations_enabled
    avatar_decorations_federation_enabled
    avatar_decorations_local_only_view
    avatar_decorations_max_count
    allow_user_custom_css
    board_announcements_enabled
    instance_metadata_enabled
    antenna_enabled
    misskey_compat_enabled
    misskey_compat_signin_flow_enabled
    misskey_compat_signin_flow_allowed_origins
    online_status_enabled
    soft_hide_deletion
    drive_enabled
    drive_quota
    drive_max_file_size
    drive_allowed_extensions
  ).freeze

  INTEGER_KEYS = %i(
    avatar_decorations_max_count
    drive_quota
    drive_max_file_size
  ).freeze

  BOOLEAN_KEYS = %i(
    force_local_only
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
    avatar_decorations_enabled
    avatar_decorations_federation_enabled
    avatar_decorations_local_only_view
    rate_limit_bypass_enabled
    allow_user_custom_css
    board_announcements_enabled
    instance_metadata_enabled
    antenna_enabled
    misskey_compat_enabled
    misskey_compat_signin_flow_enabled
    online_status_enabled
    soft_hide_deletion
    drive_enabled
  ).freeze

  included do
    validates :local_account_statuses_access, inclusion: { in: Form::AdminSettings::FEED_ACCESS_MODES }, if: -> { defined?(@local_account_statuses_access) }
    validates :local_status_page_access, inclusion: { in: Form::AdminSettings::FEED_ACCESS_MODES }, if: -> { defined?(@local_status_page_access) }
    validates :drive_quota, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, if: -> { defined?(@drive_quota) }
    validates :drive_max_file_size, numericality: { only_integer: true, greater_than: 0 }, if: -> { defined?(@drive_max_file_size) }
    validates :theme_color, format: { with: /\A#(?:[0-9a-fA-F]{3}){1,2}\z/ }, if: -> { defined?(@theme_color) }
    validate :validate_drive_allowed_extensions, if: -> { defined?(@drive_allowed_extensions) }
    validate :validate_misskey_signin_origins, if: -> { defined?(@misskey_compat_signin_flow_allowed_origins) }
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
end
