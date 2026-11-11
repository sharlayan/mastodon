# frozen_string_literal: true

class Api::V1::Chat::VoiceCallsController < Api::V1::Chat::BaseController
  STATES_LIMIT = 40
  RELAY_ERRORS = {
    'CAPACITY_EXCEEDED' => ['VOICE_RELAY_CAPACITY_EXCEEDED', 503],
    'CLIENT_DISABLED' => ['VOICE_RELAY_REVOKED', 503],
    'ALLOCATION_CONFLICT' => ['VOICE_CALL_BUSY', 409],
    'REMOTE_HOST_UNSUPPORTED' => ['REMOTE_HOST_UNSUPPORTED', 422],
    'REMOTE_HOST_UNREACHABLE' => ['REMOTE_HOST_UNREACHABLE', 503],
  }.freeze

  before_action :authorize_chat_read!, only: [:index, :show]
  before_action :authorize_chat_write!, except: [:index, :show]
  before_action :enforce_voice_call_rate_limit!, except: [:index, :show]
  before_action :set_conversation, except: :index

  rescue_from Sharlayan::VoiceCallService::Unavailable, with: :render_voice_unavailable
  rescue_from Sharlayan::VoiceCallService::Forbidden, with: :render_chat_forbidden
  rescue_from Sharlayan::VoiceCallService::Removed, with: :render_voice_removed
  rescue_from Sharlayan::VoiceRelay::Error, with: :render_voice_relay_error

  def index
    ids = Array(params[:conversation_ids]).first(STATES_LIMIT)
    raise Mastodon::InvalidParameterError, 'conversation_ids must be ids' unless ids.all? { |id| id.is_a?(String) || id.is_a?(Integer) }

    conversations = ChatConversation.for_account(current_account).where(id: ids).preload(:owner_account, :accounts).to_a
    allocations = VoiceCallAllocation.where(chat_conversation_id: conversations.map(&:id)).index_by(&:chat_conversation_id)
    remote_states = VoiceCallRemoteState.where(chat_conversation_id: conversations.reject(&:local?).map(&:id)).index_by(&:chat_conversation_id)
    relay_usable = VoiceRelayProvider.usable.exists?
    accounts = Sharlayan::VoiceCallService.participant_accounts(allocations.values + remote_states.values)

    render json: conversations.map { |conversation| Sharlayan::VoiceCallService.state_for(conversation, allocations[conversation.id], relay_usable:, accounts:, remote_state: remote_states[conversation.id]) }
  end

  def show
    render json: Sharlayan::VoiceCallService.state_for(@conversation)
  end

  def join
    render json: voice_call_service.join(current_account, @conversation)
  end

  def status
    accepted = voice_call_service.report_status(
      current_account,
      @conversation,
      session_id: params[:session_id],
      mic_muted: boolean_param(:mic_muted),
      deafened: boolean_param(:deafened)
    )

    render json: { accepted: }
  end

  def kick
    render json: { accepted: voice_call_service.kick(current_account, @conversation, target_account) }
  end

  def mute
    render json: { accepted: voice_call_service.mute(current_account, @conversation, target_account) }
  end

  private

  def enforce_voice_call_rate_limit!
    return if Setting.rate_limit_bypass_enabled && current_user.can_extra?(:bypass_rate_limit)

    RateLimiter.new(current_account, family: :voice_calls).record!
  end

  def voice_call_service
    @voice_call_service ||= Sharlayan::VoiceCallService.new
  end

  def target_account
    Account.find(chat_id_param(:account_id))
  end

  def boolean_param(key)
    value = params[key]
    raise Mastodon::InvalidParameterError, "Invalid boolean for #{key}" unless [true, false, 'true', 'false', '1', '0'].include?(value)

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def render_voice_unavailable
    render json: { error: 'VOICE_CALL_UNAVAILABLE' }, status: 422
  end

  def render_voice_removed
    render json: { error: 'VOICE_CALL_REMOVED' }, status: 403
  end

  def render_voice_relay_error(error)
    code, status = RELAY_ERRORS[error.code] || (error.revoked? ? ['VOICE_RELAY_REVOKED', 503] : ['VOICE_RELAY_UNREACHABLE', 503])
    render json: { error: code }, status:
  end
end
