# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    module ChatScope
      VALUES = %w(everyone followers following mutual none).freeze
      LEGACY_VALUES = { 'mutuals' => 'mutual', 'nobody' => 'none' }.freeze

      def self.normalize(value, default: 'mutual')
        scope = LEGACY_VALUES.fetch(value, value)
        VALUES.include?(scope) ? scope : default
      end
    end
  end
end
