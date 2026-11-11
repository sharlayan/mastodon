# frozen_string_literal: true

module Sharlayan
  module VoiceCallFederation
    class RemoteJoin
      include Redisable

      RESPONSE_LIMIT = 64.kilobytes
      MAX_TOKEN_LENGTH = 16_384
      UNSUPPORTED_TTL = 1.hour
      Error = Sharlayan::VoiceRelay::Error

      def initialize(account, conversation)
        @account = account
        @conversation = conversation
        @owner = conversation.owner_account
      end

      def join(screen_share: true)
        origin = trusted_origin!
        raise Error.new('REMOTE_HOST_UNSUPPORTED', 404) if redis.exists?(unsupported_key)

        body = { room: room_uri, canScreenShare: screen_share && Sharlayan::VoiceCallService.permitted?(@account, :share_screens) }
        response = signed_post("#{origin}/livekit/federation/token", body, remember_unsupported: true)
        credentials = parse_token_response(response, origin)

        store_participants(credentials[:participants], credentials[:updated_at])
        remember_session(credentials[:token], origin)
        credentials.except(:participants, :updated_at).merge(allow_screen_share: body[:canScreenShare])
      end

      def report_status(session_id:, mic_muted:, deafened:)
        origin = trusted_origin!
        raise Error.new('REMOTE_HOST_UNSUPPORTED', 404) if redis.exists?(unsupported_key)

        signed_post("#{origin}/livekit/federation/status", { room: room_uri, sessionId: session_id, micMuted: mic_muted, deafened: deafened }, remember_unsupported: false)
        true
      end

      private

      def trusted_origin!
        raise Sharlayan::VoiceCallService::Unavailable unless Sharlayan::VoiceCallService.remote_available?(@conversation)

        origin = Sharlayan::VoiceCallFederation.origin_of(@owner.uri)
        raise Sharlayan::VoiceCallService::Unavailable unless origin&.start_with?('https://') && Addressable::URI.parse(origin).host == @owner.domain

        origin
      end

      def room_uri
        @conversation.uri
      end

      def unsupported_key
        "voice_call:remote_unsupported:#{@owner.domain}"
      end

      def signed_post(url, body, remember_unsupported:)
        Request.new(:post, url, body: JSON.generate(body), follow: false)
          .on_behalf_of(@account)
          .add_headers('Content-Type' => 'application/json', 'Accept' => 'application/json')
          .perform do |response|
          handle_response(response, remember_unsupported:)
        end
      rescue Error, Sharlayan::VoiceCallService::Unavailable
        raise
      rescue *Sharlayan::VoiceRelay::Client::NETWORK_ERRORS
        raise Error, 'REMOTE_HOST_UNREACHABLE'
      end

      def handle_response(response, remember_unsupported:)
        case response.code
        when 200...300
          parse_json(response.body_with_limit(RESPONSE_LIMIT))
        when 404
          redis.set(unsupported_key, '1', ex: UNSUPPORTED_TTL.to_i) if remember_unsupported
          raise Error.new('REMOTE_HOST_UNSUPPORTED', 404)
        when 401, 403
          raise Sharlayan::VoiceCallService::Unavailable
        else
          raise Error.new('REMOTE_HOST_UNREACHABLE', response.code)
        end
      end

      def parse_json(body)
        body.present? ? JSON.parse(body) : {}
      rescue JSON::ParserError, EncodingError
        raise Error, 'REMOTE_HOST_UNREACHABLE'
      end

      def parse_token_response(value, origin)
        invalid = Error.new('REMOTE_HOST_UNREACHABLE')
        raise invalid unless value.is_a?(Hash) && value['url'] == "#{origin}#{Sharlayan::VoiceCallFederation::SIGNAL_PATH}"
        raise invalid unless value['token'].is_a?(String) && value['token'].length.between?(1, MAX_TOKEN_LENGTH) && room_name_of(value['token'])
        raise invalid unless value['updatedAt'].is_a?(Numeric) && value['updatedAt'].finite?

        participants = RemoteStates.parse_participants(value['participants'], identity_key: 'identity')
        raise invalid if participants.nil?

        limits = nil
        unless value['screenShareLimits'].nil?
          limits = Sharlayan::VoiceRelay::ScreenShareLimits.parse(value['screenShareLimits'])
          raise invalid if limits.nil?
        end

        provider = media_provider(value['mediaProvider'])
        {
          url: "#{Sharlayan::VoiceCallService.signal_url}/remote",
          token: value['token'],
          identity: Sharlayan::VoiceCallService.identity_for(@account),
          media_provider: provider || origin,
          ice_servers: ice_servers(value['iceServers']),
          screen_share_limits: limits,
          max_participants: Sharlayan::VoiceCallService.slots_for(@conversation),
          participants:,
          updated_at: value['updatedAt'].to_i,
        }
      end

      def media_provider(value)
        return unless value.is_a?(String)

        Sharlayan::VoiceCallFederation.origin_of(value) == value && value.start_with?('https://') ? value : nil
      end

      def ice_servers(value)
        Sharlayan::VoiceRelay::Responses.ice_servers(value) || []
      rescue Error
        []
      end

      def room_name_of(token)
        payload = JSON.parse(Base64.urlsafe_decode64(token.split('.')[1].to_s.then { |part| part + ('=' * ((4 - (part.length % 4)) % 4)) }))
        room = payload.is_a?(Hash) && payload['video'].is_a?(Hash) ? payload['video']['room'] : nil
        room.is_a?(String) && room.length.between?(1, 512) ? room : nil
      rescue ArgumentError, JSON::ParserError, EncodingError
        nil
      end

      def store_participants(participants, updated_at)
        RemoteStates.store(@conversation, participants, updated_at)
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn("Could not store the voice call state of chat #{@conversation.id}: #{e.message}")
      end

      def remember_session(token, origin)
        identity = Sharlayan::VoiceCallService.identity_for(@account)
        room_name = room_name_of(token)
        VoiceCallRemoteSession.upsert(
          { account_id: @account.id, chat_conversation_id: @conversation.id, identity:, room_name:, origin:, expires_at: VoiceCallRemoteSession::LIFETIME.from_now, created_at: Time.now.utc, updated_at: Time.now.utc },
          unique_by: :index_voice_call_remote_sessions_on_identity_and_room
        )
      end
    end
  end
end
