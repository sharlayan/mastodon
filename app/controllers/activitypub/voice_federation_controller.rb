# frozen_string_literal: true

class ActivityPub::VoiceFederationController < ActivityPub::BaseController
  MAX_BODY_SIZE = 16.kilobytes
  MAX_ROOM_URI_LENGTH = 2048

  before_action :require_host_enabled!
  before_action :require_small_body!
  before_action :require_account_signature!
  before_action :require_remote_account!
  before_action :enforce_voice_call_rate_limit!
  before_action :disable_caching

  def capability
    conversation = conversation_for(params[:room])
    return head 403 unless conversation && Sharlayan::VoiceCallService.joinable?(conversation) && member?(conversation)

    render json: { includeIceServers: true }
  end

  def token
    body = json_body
    return head 400 unless body && room_param?(body['room']) && optional_boolean?(body['canScreenShare']) && optional_boolean?(body['includeIceServers'])

    conversation = conversation_for(body['room'])
    return head 403 if conversation.nil?

    credentials = Sharlayan::VoiceCallService.new.join(signed_request_account, conversation, screen_share: body['canScreenShare'] == true)
    render json: token_response(conversation, credentials, include_ice_servers: body['includeIceServers'] != false)
  rescue Sharlayan::VoiceCallService::Unavailable, Sharlayan::VoiceCallService::Forbidden
    head 403
  rescue Sharlayan::VoiceRelay::Error
    head 503
  end

  def status
    body = json_body
    return head 400 unless body && room_param?(body['room']) && body['sessionId'].is_a?(String) && body['sessionId'].length.between?(1, 128) && boolean?(body['micMuted']) && boolean?(body['deafened'])

    conversation = conversation_for(body['room'])
    return head 403 if conversation.nil?

    accepted = Sharlayan::VoiceCallService.new.report_status(signed_request_account, conversation, session_id: body['sessionId'], mic_muted: body['micMuted'], deafened: body['deafened'])
    accepted ? render(json: {}) : head(403)
  rescue Sharlayan::VoiceCallService::Unavailable, Sharlayan::VoiceCallService::Forbidden, Sharlayan::VoiceRelay::Error
    head 403
  end

  private

  def account_required?
    false
  end

  def require_host_enabled!
    head 404 unless Sharlayan::VoiceCallFederation.host_enabled?
  end

  def require_small_body!
    head 413 if request.content_length.to_i > MAX_BODY_SIZE
  end

  def require_remote_account!
    head 403 unless Sharlayan::VoiceCallFederation.remote_account_permitted?(signed_request_account)
  end

  def enforce_voice_call_rate_limit!
    RateLimiter.new(signed_request_account, family: :voice_calls).record!
  end

  def disable_caching
    response.headers['Cache-Control'] = 'no-store'
  end

  def json_body
    value = JSON.parse(request.raw_post)
    value.is_a?(Hash) ? value : nil
  rescue JSON::ParserError
    nil
  end

  def room_param?(value)
    value.is_a?(String) && value.length <= MAX_ROOM_URI_LENGTH
  end

  def boolean?(value)
    [true, false].include?(value)
  end

  def optional_boolean?(value)
    value.nil? || boolean?(value)
  end

  def conversation_for(room)
    return unless room_param?(room)

    id = Sharlayan::VoiceCallFederation.local_room_id(room)
    conversation = id && ChatConversation.find_by(id:)
    conversation if conversation&.local?
  end

  def member?(conversation)
    ChatMembership.exists?(chat_conversation_id: conversation.id, account_id: signed_request_account.id)
  end

  def token_response(conversation, credentials, include_ice_servers:)
    allocation = VoiceCallAllocation.find_by(chat_conversation_id: conversation.id)
    stamp = Sharlayan::VoiceCallFederation::Outgoing.stamp(conversation.id)
    response = {
      url: Sharlayan::VoiceCallFederation.signal_url_for(conversation.owner_account),
      token: credentials[:token],
      iceServers: include_ice_servers ? credentials[:ice_servers] : nil,
      participants: Sharlayan::VoiceCallFederation.participant_entries(allocation&.active? ? allocation.participants : [], key: 'identity'),
      updatedAt: stamp,
      mediaProvider: credentials[:media_provider],
    }
    response[:screenShareLimits] = credentials[:screen_share_limits] if credentials[:screen_share_limits]
    response
  end
end
