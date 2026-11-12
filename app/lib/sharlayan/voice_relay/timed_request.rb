# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    class TimedRequest < ::Request
      def initialize(verb, url, timeout:, **)
        super(verb, url, **)

        @options = @options.merge(timeout_options: TIMEOUT.transform_values { |value| [value, timeout].min })
      end
    end
  end
end
