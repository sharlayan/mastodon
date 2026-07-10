# frozen_string_literal: true

class Api::MisskeyCompat::BaseController < ApplicationController
  include Authorization
  include RoutingHelper

  wrap_parameters false

  skip_before_action :verify_authenticity_token, raise: false

  before_action :require_misskey_compat_enabled!

  INVALID_PARAM_ID = '3d81ceae-475f-4600-b2a8-2bc116157532'

  RequesterIdentity = Struct.new(:id)

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

  def current_token
    return @current_token if defined?(@current_token)

    token = params[:i].presence
    @current_token = token ? Doorkeeper::AccessToken.by_token(token.to_s) : nil
    @current_token = nil if @current_token&.revoked?
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
    render_error('Authentication required', 'CREDENTIAL_REQUIRED', 401) if current_user.nil?
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
      canUseTranslator: false,
      canUseReaction: true,
      canHideAds: false,
      avatarDecorationLimit: avatar_decoration_limit,
    }
  end

  def avatar_decoration_limit
    return 0 unless Setting.avatar_decorations_enabled

    Setting.avatar_decorations_max_count.to_i.clamp(0, UpdateAccountService::MAX_DECORATIONS)
  end
end
