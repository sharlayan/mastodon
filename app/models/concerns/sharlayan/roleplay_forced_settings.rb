# frozen_string_literal: true

module Sharlayan::RoleplayForcedSettings
  DEFAULT_SETTINGS = {
    avatar_decorations_enabled: false,
    circles_enabled: false,
    online_status_enabled: false,
    rate_limit_bypass_enabled: true,
    reactions_enabled: false,
    roleplay_disable_local_timeline: false,
    roleplay_hide_public_timelines_from_admins: false,
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
    local_live_feed_access: 'disabled',
    remote_live_feed_access: 'disabled',
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
      setting.update!(value: value) if setting.new_record?
    end
  end

  # DESTRUCTIVE: Rewrites forced settings while roleplay mode is enabled.
  # 파괴적: 자캐 커뮤니티 모드가 켜진 동안 강제 설정을 덮어씁니다.
  def self.apply_forced!
    SETTINGS.each do |var, value|
      setting = Setting.where(var: var.to_s).first_or_initialize(var: var.to_s)
      setting.update!(value: value) unless setting.value == value
    end
  end
end
