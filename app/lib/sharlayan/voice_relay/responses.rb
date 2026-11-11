# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    module Responses
      STATES = %w(pending active ending ended).freeze
      DIGITS = /\A\d+\z/
      MAX_TOKEN_LENGTH = 16_384
      MAX_EVENTS = 100
      MAX_CURSOR_LENGTH = 256
      MAX_ICE_SERVERS = 16
      MAX_ICE_URLS = 16
      ICE_CREDENTIAL_KEYS = %w(username credential).freeze
      PARTICIPANT_TEXT_KEYS = %w(identity userId sessionId).freeze

      module_function

      def allocation(value, generation:, slots:)
        raise invalid unless value['id'].is_a?(String) && VoiceCallAllocation::REMOTE_ID_PATTERN.match?(value['id'])
        raise invalid unless value['generation'] == generation && value['reservedSlots'] == slots && STATES.include?(value['state'])

        value
      end

      def ended(value, allocation)
        raise invalid unless value['state'] == 'ended' && value['id'] == allocation.remote_id && value['generation'] == allocation.generation

        value
      end

      def join(value, allocation)
        raise invalid unless value['token'].is_a?(String) && value['token'].length.between?(1, MAX_TOKEN_LENGTH)
        raise invalid unless value['allocationId'] == allocation.remote_id && value['generation'] == allocation.generation
        raise invalid unless value['mediaProvider'].is_a?(String) && value['mediaProvider'].length <= 2048

        limits = nil
        unless value['screenShareLimits'].nil?
          limits = ScreenShareLimits.parse(value['screenShareLimits'])
          raise invalid if limits.nil?
        end

        {
          token: value['token'],
          media_provider: value['mediaProvider'],
          ice_servers: ice_servers(value['iceServers']),
          screen_share_limits: limits,
        }
      end

      def ice_servers(value)
        return nil if value.nil?
        raise invalid unless value.is_a?(Array) && value.size <= MAX_ICE_SERVERS

        value.map do |server|
          raise invalid unless server.is_a?(Hash) && server['urls'].is_a?(Array) && server['urls'].size.between?(1, MAX_ICE_URLS)
          raise invalid unless server['urls'].all? { |url| url.is_a?(String) && url.length <= 2048 && /\A(stuns?|turns?):/i.match?(url) }

          entry = { urls: server['urls'] }
          ICE_CREDENTIAL_KEYS.each do |key|
            next if server[key].nil?
            raise invalid unless server[key].is_a?(String) && server[key].length <= 2048

            entry[key.to_sym] = server[key]
          end
          entry
        end
      end

      def snapshot(value, allocation)
        raise invalid unless value['allocationId'] == allocation.remote_id && value['generation'] == allocation.generation
        raise invalid unless STATES.include?(value['state']) && value['revision'].is_a?(String) && DIGITS.match?(value['revision'])
        raise invalid unless value['participants'].is_a?(Array) && value['participants'].size <= allocation.slots

        participants = value['participants'].map do |participant|
          raise invalid unless participant.is_a?(Hash) && PARTICIPANT_TEXT_KEYS.all? { |key| participant[key].is_a?(String) && participant[key].length <= 2048 }
          raise invalid unless Capacity.boolean?(participant['screenSharing']) && Capacity.boolean?(participant['allowScreenShare'])

          {
            'identity' => participant['identity'],
            'user_id' => participant['userId'],
            'session_id' => participant['sessionId'],
            'screen_sharing' => participant['screenSharing'],
            'allow_screen_share' => participant['allowScreenShare'],
            'mic_muted' => participant['micMuted'] == true,
            'deafened' => participant['deafened'] == true,
          }
        end

        { state: value['state'], revision: value['revision'], participants: }
      end

      def events(value)
        raise invalid unless value['events'].is_a?(Array) && value['events'].size <= MAX_EVENTS
        raise invalid unless value['cursor'].is_a?(String) && value['cursor'].length <= MAX_CURSOR_LENGTH && Capacity.boolean?(value['gap'])

        touched = value['events'].map do |event|
          raise invalid unless event.is_a?(Hash) && event['allocationId'].is_a?(String) && event['generation'].is_a?(String)

          [event['allocationId'], event['generation']]
        end

        { touched: touched.uniq, cursor: value['cursor'], gap: value['gap'] }
      end

      def accepted(value)
        raise invalid unless Capacity.boolean?(value['accepted'])

        value['accepted']
      end

      def invalid
        Error.new('INVALID_RESPONSE')
      end
    end
  end
end
