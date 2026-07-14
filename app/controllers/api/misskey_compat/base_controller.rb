# frozen_string_literal: true

class Api::MisskeyCompat::BaseController < ApplicationController
  include Authorization
  include RoutingHelper

  wrap_parameters false

  skip_before_action :verify_authenticity_token, raise: false

  before_action :require_misskey_compat_enabled!
  before_action :decode_mi_ids!

  INVALID_PARAM_ID = '3d81ceae-475f-4600-b2a8-2bc116157532'

  MI_ID_SCALAR_PARAMS = %i(untilId sinceId userId noteId roleId clipId replyId renoteId listId antennaId announcementId avatarId bannerId folderId fileId channelId draftId).freeze
  MI_ID_ARRAY_PARAMS = %i(fileIds visibleUserIds userIds noteIds).freeze

  RequesterIdentity = Struct.new(:id)

  class_attribute :misskey_write_actions, instance_writer: false, default: []

  def self.requires_write_scope(*actions)
    self.misskey_write_actions = (misskey_write_actions + actions.map(&:to_s)).uniq.freeze
  end

  rescue_from ArgumentError do |e|
    render_invalid_param('#/', e.to_s)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error(e.to_s, 'INVALID_PARAM', 400)
  end

  private

  def rate_limited?(family)
    RateLimiter.new(current_account || RequesterIdentity.new(request.remote_ip), family: family).record!
    false
  rescue Mastodon::RateLimitExceededError
    render_error(I18n.t('errors.429'), 'RATE_LIMIT_EXCEEDED', 429)
    true
  end

  def require_misskey_compat_enabled!
    render_error('This endpoint is not available', 'ENDPOINT_DISABLED', 404) unless Setting.misskey_compat_enabled
  end

  def decode_mi_ids!
    MI_ID_SCALAR_PARAMS.each do |key|
      value = params[key]
      params[key] = MisskeyCompat::MiId.decode(value) if value.is_a?(String)
    end

    MI_ID_ARRAY_PARAMS.each do |key|
      value = params[key]
      params[key] = value.map { |item| item.is_a?(String) ? MisskeyCompat::MiId.decode(item) : item } if value.is_a?(Array)
    end
  end

  def current_token
    return @current_token if defined?(@current_token)

    token = params[:i].presence
    @current_token = token ? Doorkeeper::AccessToken.by_token(token.to_s) : nil
    @current_token = nil unless @current_token&.accessible?
    @current_token
  end

  # rubocop:disable Naming/MemoizedInstanceVariableName
  def current_user
    return @misskey_current_user if defined?(@misskey_current_user)

    @misskey_current_user = current_token ? User.find_by(id: current_token.resource_owner_id) : nil
  end
  # rubocop:enable Naming/MemoizedInstanceVariableName

  def current_account
    current_user&.account
  end

  def require_user!
    if current_user.nil?
      code = params[:i].present? ? 'AUTHENTICATION_FAILED' : 'CREDENTIAL_REQUIRED'
      render_error('Authentication required', code, 401)
    elsif !current_token.scopes.exists?(required_token_scope)
      render_error('Insufficient token scope', 'PERMISSION_DENIED', 403)
    end
  end

  def required_token_scope
    misskey_write_actions.include?(action_name) ? 'write' : 'read'
  end

  def render_error(message, code, status, id: nil, kind: 'client', info: nil)
    error = { message: message, code: code, id: id, kind: kind }
    error[:info] = info unless info.nil?
    render json: { error: error.compact }, status: status
  end

  def render_invalid_param(param, reason)
    render_error('Invalid param.', 'INVALID_PARAM', 400, id: INVALID_PARAM_ID, info: { param: param, reason: reason }) # rubocop:disable I18n/RailsI18n/DecorateString
  end

  def object_body!
    raw = request.raw_post
    return true if raw.nil? || raw.strip.empty?

    JSON.parse(raw).is_a?(Hash).tap do |ok|
      render_invalid_param('#/type', 'must be object') unless ok
    end
  rescue JSON::ParserError
    render_invalid_param('#/type', 'must be object')
    false
  end

  def pagination_limit(default: 20, max: 40)
    limit = params[:limit].to_i
    limit = default if limit <= 0
    limit.clamp(1, max)
  end

  def apply_user_origin(scope)
    case params[:origin].to_s
    when 'local'
      scope.local
    when 'remote'
      scope.remote
    else
      scope
    end
  end

  def apply_user_sort(scope)
    case params[:sort].to_s
    when '-follower'
      scope.order('account_stats.followers_count ASC')
    when '+createdAt'
      scope.order('accounts.id DESC')
    when '-createdAt'
      scope.order('accounts.id ASC')
    when '+updatedAt'
      scope.order(Arel.sql('account_stats.last_status_at DESC NULLS LAST'))
    when '-updatedAt'
      scope.order(Arel.sql('account_stats.last_status_at ASC NULLS FIRST'))
    else
      scope.order('account_stats.followers_count DESC')
    end
  end

  def compat_policies
    {
      gtlAvailable: true,
      ltlAvailable: true,
      canPublicNote: true,
      canInitiateConversation: true,
      canCreateContent: true,
      canUpdateContent: true,
      canDeleteContent: true,
      canPurgeAccount: true,
      canUpdateAvatar: true,
      canUpdateBanner: true,
      canManageCustomEmojis: false,
      canManageAvatarDecorations: false,
      canSearchNotes: true,
      canUseTranslator: TranslationService.configured?,
      canUseReaction: true,
      canHideAds: false,
      canScheduleNote: true,
      scheduleNoteMax: ScheduledStatus::TOTAL_LIMIT,
      scheduleNoteMaxDays: 0,
      avatarDecorationLimit: avatar_decoration_limit,
    }
  end

  def avatar_decoration_limit
    return 0 unless Setting.avatar_decorations_enabled

    Setting.avatar_decorations_max_count.to_i.clamp(0, UpdateAccountService::MAX_DECORATIONS)
  end
end
