# frozen_string_literal: true

module Sharlayan::SettingExtensions
  MIN_STATUS_CHARACTER_LIMIT = 300

  module_function

  def merge_defaults(defaults)
    defaults.merge(sharlayan_defaults)
  end

  def sharlayan_defaults
    content = Rails.root.join('config', 'settings', 'sharlayan.yml').read
    defaults = YAML.safe_load(content).fetch('defaults')
    configured_status_limit = Integer(ENV.fetch('MAX_TOOT_CHARS', ''), exception: false)
    defaults['status_character_limit'] = configured_status_limit if configured_status_limit&.>= MIN_STATUS_CHARACTER_LIMIT
    defaults['profile_fields_limit'] = ENV.fetch('MAX_PROFILE_FIELDS', defaults.fetch('profile_fields_limit')).to_i.clamp(0, ActivityPub::ProcessAccountService::MAX_PROFILE_FIELDS)
    defaults['remote_media_attachments_limit'] = ENV.fetch('REMOTE_MEDIA_ATTACHMENTS_LIMIT', defaults.fetch('remote_media_attachments_limit')).to_i.clamp(Status::MEDIA_ATTACHMENTS_LIMIT, 16)
    defaults
  end
end
