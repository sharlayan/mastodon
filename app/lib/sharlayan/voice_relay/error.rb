# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    class Error < StandardError
      attr_reader :code, :status

      def initialize(code, status = 503)
        @code = code
        @status = status
        super(code)
      end

      def revoked?
        [401, 403].include?(status)
      end
    end
  end
end
