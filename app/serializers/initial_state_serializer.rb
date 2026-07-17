# frozen_string_literal: true

class InitialStateSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :meta, :compose, :accounts,
             :media_attachments, :settings,
             :max_feed_hashtags, :poll_limits,
             :languages, :max_reactions,
             :features

  attribute :critical_updates_pending, if: -> { object&.role&.can?(:view_devops) && SoftwareUpdate.check_enabled? }

  has_one :push_subscription, serializer: REST::WebPushSubscriptionSerializer
  has_one :role, serializer: REST::RoleSerializer

  def max_reactions
    StatusReactionValidator::LIMIT
  end

  def max_feed_hashtags
    TagFeed::LIMIT_PER_MODE
  end

  def poll_limits
    {
      max_options: PollOptionsValidator::MAX_OPTIONS,
      max_option_chars: PollOptionsValidator::MAX_OPTION_CHARS,
      min_expiration: PollExpirationValidator::MIN_EXPIRATION,
      max_expiration: PollExpirationValidator::MAX_EXPIRATION,
    }
  end

  def meta
    store = default_meta_store

    if object.current_account
      store[:me]                = object.current_account.id.to_s
      store[:boost_modal]       = object_account_user.setting_boost_modal
      store[:favourite_modal]   = object_account_user.setting_favourite_modal
      store[:quick_boosting]    = object_account_user.setting_quick_boosting
      store[:delete_modal]      = object_account_user.setting_delete_modal
      store[:missing_alt_text_modal] = object_account_user.settings['web.missing_alt_text_modal']
      store[:auto_play_gif]     = object_account_user.setting_auto_play_gif
      store[:display_media]     = object_account_user.setting_display_media
      store[:expand_spoilers]   = object_account_user.setting_expand_spoilers
      store[:reduce_motion]     = object_account_user.setting_reduce_motion
      store[:disable_swiping]   = object_account_user.setting_disable_swiping
      store[:disable_hover_cards] = object_account_user.setting_disable_hover_cards
      store[:advanced_layout]   = object_account_user.setting_advanced_layout
      store[:use_blurhash]      = object_account_user.setting_use_blurhash
      store[:use_pending_items] = object_account_user.setting_use_pending_items
      store[:default_content_type] = object_account_user.setting_default_content_type
      store[:show_trends]       = Setting.trends && object_account_user.setting_trends
      store[:visible_reactions] = object_account_user.setting_visible_reactions
      store[:emoji_style]       = object_account_user.settings['web.emoji_style']
      store[:show_instance_info]          = object_account_user.settings_show_instance_info
      store[:custom_emoji_size]           = object_account_user.settings_custom_emoji_size
      store[:reaction_custom_emoji_size]  = object_account_user.settings_reaction_custom_emoji_size
      store[:reaction_local_emoji_only]   = Setting.reaction_local_emoji_only
      store[:reactions_enabled]           = Setting.reactions_enabled
      store[:mfm_enabled]                 = object_account_user.settings_mfm_enabled
      store[:mfm_animations]              = object_account_user.settings_mfm_animations
      store[:mfm_fold_mode]               = object_account_user.settings_mfm_fold_mode
      store[:mfm_allow_composition]       = Setting.mfm_allow_composition
      store[:wrapstodon] = wrapstodon
      store[:show_avatar_decorations]           = object_account_user.settings['avatar_decorations.show']
      store[:show_federated_avatar_decorations] = object_account_user.settings['avatar_decorations.show_federated']
      store[:avatar_decoration_shape]           = object_account_user.settings['avatar_decorations.shape']
      store[:color_scheme]                      = object_account_user.settings['web.color_scheme']
      store[:contrast]                          = object_account_user.settings['web.contrast']
      store[:custom_emoji_mute_hidden]          = object_account_user.settings['web.custom_emoji_mute_hidden']
      store[:custom_emoji_mutes]                = object.current_account.custom_emoji_mutes.order(id: :desc).map { |mute| { id: mute.id.to_s, prefix: mute.prefix, domain: mute.domain, reject_reactions: mute.reject_reactions, hide_in_picker: mute.hide_in_picker } }
      store[:reaction_mutes]                    = object.current_account.reaction_mutes.includes(:target_account).order(id: :desc).map { |mute| { id: mute.id.to_s, target_account_id: mute.target_account_id&.to_s, target_acct: mute.target_account&.acct, target_domain: mute.target_domain } }
    else
      store[:auto_play_gif] = Setting.auto_play_gif
      store[:display_media] = Setting.display_media
      store[:reduce_motion] = Setting.reduce_motion
      store[:use_blurhash]  = Setting.use_blurhash
    end

    store[:disabled_account_id] = object.disabled_account.id.to_s if object.disabled_account
    store[:moved_to_account_id] = object.moved_to_account.id.to_s if object.moved_to_account

    store[:owner] = object.owner&.id&.to_s if Rails.configuration.x.single_user_mode

    store
  end

  def compose
    store = {}

    if object.current_account
      store[:me]                = object.current_account.id.to_s
      store[:default_privacy]   = object.visibility || object_account_user.setting_default_privacy
      store[:default_sensitive] = object_account_user.setting_default_sensitive
      store[:default_language]  = object_account_user.preferred_posting_language
      store[:default_quote_policy] = object_account_user.setting_default_quote_policy
    end

    store[:text] = object.text if object.text

    store
  end

  def accounts
    store = {}

    ActiveRecord::Associations::Preloader.new(
      records: [object.current_account, object.admin, object.owner, object.disabled_account, object.moved_to_account].compact,
      associations: [:account_stat, { user: :role, moved_to_account: [:account_stat, { user: :role }] }]
    ).call

    store[object.current_account.id.to_s]  = serialized_account(object.current_account) if object.current_account
    store[object.admin.id.to_s]            = serialized_account(object.admin) if object.admin
    store[object.owner.id.to_s]            = serialized_account(object.owner) if object.owner
    store[object.disabled_account.id.to_s] = serialized_account(object.disabled_account) if object.disabled_account
    store[object.moved_to_account.id.to_s] = serialized_account(object.moved_to_account) if object.moved_to_account

    store
  end

  def media_attachments
    { accept_content_types: MediaAttachment.supported_file_extensions + MediaAttachment.supported_mime_types }
  end

  def languages
    LanguagesHelper::SUPPORTED_LOCALES.map { |(key, value)| [key, value[0], value[1]] }
  end

  def features
    Mastodon::Feature.enabled_features
  end

  private

  def wrapstodon
    current_campaign = AnnualReport.current_campaign
    return if current_campaign.blank?

    {
      year: current_campaign,
      state: AnnualReport.new(object.current_account, current_campaign).state,
    }
  end

  def default_meta_store
    {
      access_token: object.token,
      activity_api_enabled: Setting.activity_api_enabled,
      admin: object.admin&.id&.to_s,
      domain: Addressable::IDNA.to_unicode(instance_presenter.domain),
      limited_federation_mode: Rails.configuration.x.mastodon.limited_federation_mode,
      locale: I18n.locale,
      mascot: instance_presenter.mascot&.file&.url,
      profile_directory: Setting.profile_directory,
      registrations_open: Setting.registrations_mode != 'none' && !Rails.configuration.x.single_user_mode,
      repository: Mastodon::Version.repository,
      search_enabled: Chewy.enabled?,
      single_user_mode: Rails.configuration.x.single_user_mode,
      source_url: instance_presenter.source_url,
      sso_redirect: sso_redirect,
      status_page_url: Setting.status_page_url,
      streaming_api_base_url: Rails.configuration.x.streaming_api_base_url,
      title: instance_presenter.title,
      landing_page: Setting.landing_page,
      trends_enabled: Setting.trends,
      version: instance_presenter.version,
      terms_of_service_enabled: TermsOfService.current.present?,
      force_local_only: Setting.force_local_only,
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      antenna_enabled: Setting.antenna_enabled,
      drive_enabled: Setting.drive_enabled,
      board_announcements_enabled: Setting.board_announcements_enabled,
      avatar_decorations_enabled: Setting.avatar_decorations_enabled,
      avatar_decorations_federation_enabled: Setting.avatar_decorations_federation_enabled,
      local_account_statuses_access: Setting.local_account_statuses_access,
      local_status_page_access: Setting.local_status_page_access,
      local_live_feed_access: Setting.local_live_feed_access,
      remote_live_feed_access: Setting.remote_live_feed_access,
      local_topic_feed_access: Setting.local_topic_feed_access,
      remote_topic_feed_access: Setting.remote_topic_feed_access,
    }
  end

  def object_account
    object.current_account
  end

  def object_account_user
    object.current_account.user
  end

  def serialized_account(account)
    ActiveModelSerializers::SerializableResource.new(account, serializer: REST::AccountSerializer, scope_name: :current_user, scope: object.current_account&.user)
  end

  def instance_presenter
    @instance_presenter ||= InstancePresenter.new
  end

  def sso_redirect
    "/auth/auth/#{Devise.omniauth_providers[0]}" if ENV['ONE_CLICK_SSO_LOGIN'] == 'true' && ENV['OMNIAUTH_ONLY'] == 'true' && Devise.omniauth_providers.length == 1
  end
end
