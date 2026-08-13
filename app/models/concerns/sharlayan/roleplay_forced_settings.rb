# frozen_string_literal: true

module Sharlayan::RoleplayForcedSettings
  DEFAULT_SETTINGS = {
    avatar_decorations_enabled: false,
    circles_enabled: false,
    online_status_enabled: false,
    rate_limit_bypass_enabled: true,
    reactions_enabled: false,
    status_character_limit: 1500,
    user_themes_enabled: false,
  }.freeze

  SETTINGS = {
    antenna_enabled: false,
    cat_enabled: false,
    cat_federation_enabled: false,
    federation_instance_edges_enabled: false,
    federation_request_statistics_enabled: false,
    force_local_only: true,
    local_live_feed_access: 'authenticated',
    remote_live_feed_access: 'authenticated',
    local_topic_feed_access: 'authenticated',
    remote_topic_feed_access: 'authenticated',
    local_account_statuses_access: 'authenticated',
    local_status_page_access: 'authenticated',
    noindex: true,
    norss: true,
    allow_referrer_origin: false,
    activity_api_enabled: false,
    peers_api_enabled: false,
    authorized_fetch: true,
    trends: false,
  }.freeze

  def self.apply_defaults!
    DEFAULT_SETTINGS.each do |var, value|
      setting = Setting.where(var: var.to_s).first_or_initialize(var: var.to_s)
      setting.update(value: value) if setting.new_record?
    end
  end
end
