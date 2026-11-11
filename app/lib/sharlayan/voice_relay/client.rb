# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    class Client
      BASE_PATH = '/voice-relay/v1'
      TOKEN_TYPE = 'voice-relay-client+jwt'
      TOKEN_TTL = 60
      SECRET_MIN_LENGTH = 32
      RESPONSE_LIMIT = 64.kilobytes
      NETWORK_ERRORS = [
        HTTP::Error,
        OpenSSL::SSL::SSLError,
        Mastodon::Error,
        SystemCallError,
        IOError,
        Addressable::URI::InvalidURIError,
      ].freeze

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

      def capacity
        Capacity.parse(request(:get, '/capacity'))
      end

      def request(verb, path, body = nil)
        options = { follow: false }
        options[:body] = JSON.generate(body) unless body.nil?

        headers = { 'Authorization' => "Bearer #{bearer_token}", 'Accept' => 'application/json' }
        headers['Content-Type'] = 'application/json' unless body.nil?

        Request.new(verb, "#{Origin.normalize(@provider.origin)}#{BASE_PATH}#{path}", **options).add_headers(headers).perform do |response|
          parse_response(response)
        end
      rescue Error
        raise
      rescue *NETWORK_ERRORS
        raise Error, 'PROVIDER_UNAVAILABLE'
      end

      private

      def parse_response(response)
        value = parse_json(response.body_with_limit(RESPONSE_LIMIT))

        unless (200...300).cover?(response.code)
          code = value.is_a?(Hash) && value['code'].is_a?(String) ? value['code'].first(64) : 'PROVIDER_UNAVAILABLE'
          raise Error.new(code, response.code)
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
