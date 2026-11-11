# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    module Capacity
      MAX_SAFE_INTEGER = (2**53) - 1
      COUNT_FIELDS = %w(maxSlots reservedSlots remainingSlots remainingRooms).freeze

      module_function

      def parse(value)
        raise invalid unless value.is_a?(Hash)
        raise invalid unless value['protocolVersion'] == 1
        raise invalid unless boolean?(value['enabled']) && boolean?(value['accepting'])
        raise invalid unless COUNT_FIELDS.all? { |field| safe_integer?(value[field]) && value[field] >= 0 }
        raise invalid unless value['maxSlots'] >= 1

        result = value.slice('protocolVersion', 'enabled', 'accepting', *COUNT_FIELDS)
        result['allowScreenShare'] = value['allowScreenShare'] == true
        result['mediaProvider'] = value['mediaProvider'] if value['mediaProvider'].is_a?(String) && value['mediaProvider'].length <= 2048

        unless value['screenShareLimits'].nil?
          limits = ScreenShareLimits.parse(value['screenShareLimits'])
          raise invalid if limits.nil?

          result['screenShareLimits'] = limits
        end

        capabilities = value['capabilities'].is_a?(Hash) ? value['capabilities'] : {}
        result['capabilities'] = {
          'cancelPending' => capabilities['cancelPending'] == true,
          'includeIceServers' => capabilities['includeIceServers'] == true,
        }

        result
      end

      def safe_integer?(number)
        number.is_a?(Integer) && number.between?(-MAX_SAFE_INTEGER, MAX_SAFE_INTEGER)
      end

      def boolean?(value)
        [true, false].include?(value)
      end

      def invalid
        Error.new('INVALID_RESPONSE')
      end
    end
  end
end
