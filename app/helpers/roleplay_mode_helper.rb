# frozen_string_literal: true

module RoleplayModeHelper
  ROLEPLAY_FORCED_SETTINGS = {
    antenna_enabled: false,
    force_local_only: true,
    local_live_feed_access: 'authenticated',
    remote_live_feed_access: 'authenticated',
    local_topic_feed_access: 'authenticated',
    remote_topic_feed_access: 'authenticated',
    local_account_statuses_access: 'authenticated',
    local_status_page_access: 'authenticated',
    noindex: true,
    allow_referrer_origin: false,
    activity_api_enabled: false,
    peers_api_enabled: false,
    authorized_fetch: true,
  }.freeze

  def roleplay_mode?
    ENV['OC_ROLEPLAY_OPTION'] == 'true'
  end

  module_function :roleplay_mode?
end
