# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    class Client
      class DeadlineExceeded < Mastodon::RaceConditionError; end

      BASE_PATH = '/voice-relay/v1'
      TOKEN_TYPE = 'voice-relay-client+jwt'
      TOKEN_TTL = 60
      SECRET_MIN_LENGTH = 32
      RESPONSE_LIMIT = 64.kilobytes
      REQUEST_TIMEOUT = 10
      NETWORK_ERRORS = [
        HTTP::Error,
        OpenSSL::SSL::SSLError,
        Mastodon::Error,
        SystemCallError,
        IOError,
        Addressable::URI::InvalidURIError,
      ].freeze

      def self.with_deadline(budget)
        previous = ActiveSupport::IsolatedExecutionState[:voice_relay_deadline]
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget.to_f
        ActiveSupport::IsolatedExecutionState[:voice_relay_deadline] = previous ? [previous, deadline].min : deadline
        yield
      ensure
        ActiveSupport::IsolatedExecutionState[:voice_relay_deadline] = previous
      end

      def self.time_left(timeout)
        deadline = ActiveSupport::IsolatedExecutionState[:voice_relay_deadline]
        return timeout.to_f if deadline.nil?

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise DeadlineExceeded, 'Voice relay requests ran out of time, try again later' unless remaining.positive?

        [timeout.to_f, remaining].min
      end

      def initialize(provider)
        @provider = provider
      end

      def bearer_token(now: Time.now.to_i)
        secret = @provider.secret
        raise Error.new('MISSING_KEY', 400) if secret.blank? || secret.length < SECRET_MIN_LENGTH

        JWT.encode(
          { iss: Origin.local, aud: @provider.origin, iat: now, exp: now + TOKEN_TTL },
          secret,
          'HS256',
          { typ: TOKEN_TYPE }
        )
      end

      def capacity(timeout: REQUEST_TIMEOUT)
        Capacity.parse(request(:get, '/capacity', timeout:))
      end

      def request(verb, path, body = nil, timeout: REQUEST_TIMEOUT)
        seconds = self.class.time_left(timeout)

        options = { follow: false }
        options[:body] = JSON.generate(body) unless body.nil?

        headers = { 'Authorization' => "Bearer #{bearer_token}", 'Accept' => 'application/json' }
        headers['Content-Type'] = 'application/json' unless body.nil?

        TimedRequest.new(verb, "#{Origin.normalize(@provider.origin)}#{BASE_PATH}#{path}", timeout: seconds, **options).add_headers(headers).perform do |response|
          parse_response(response)
        end
      rescue Error, DeadlineExceeded
        raise
      rescue *NETWORK_ERRORS
        raise Error, 'PROVIDER_UNAVAILABLE'
      end

      private

      def parse_response(response)
        value = parse_json(response.body_with_limit(RESPONSE_LIMIT))

        unless (200...300).cover?(response.code)
          raise Error, 'PROVIDER_UNAVAILABLE' unless value.is_a?(Hash) && value['code'].is_a?(String)

          raise Error.new(value['code'].first(64), response.code)
        end

        raise Error, 'INVALID_RESPONSE' unless value.is_a?(Hash)

        value
      end

      def parse_json(body)
        return nil if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError, EncodingError
        nil
      end
    end
  end
end
