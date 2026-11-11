# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    module ScreenShareLimits
      FIELDS = %w(maxWidth maxHeight maxFrameRate maxBitrate).freeze

      module_function

      def parse(value)
        return nil unless value.is_a?(Hash) && value.keys.map(&:to_s).sort == FIELDS.sort

        limits = FIELDS.index_with { |field| value[field] }
        return nil unless limits.values.all? { |number| Capacity.safe_integer?(number) && number >= 1 }

        limits
      end
    end
  end
end
