# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    module Origin
      IPV4_PATTERN = /\A\d{1,3}(\.\d{1,3}){3}\z/

      module_function

      def normalize(value)
        raise invalid unless value.is_a?(String)

        uri = Addressable::URI.parse(value.strip)
        host = uri.normalized_host.to_s.downcase.delete_suffix('.')

        raise invalid unless uri.scheme&.downcase == 'https'
        raise invalid if uri.userinfo.present? || uri.query || uri.fragment
        raise invalid unless ['', '/'].include?(uri.path)
        raise invalid if host.blank? || host.start_with?('[') || host.include?(':') || IPV4_PATTERN.match?(host)
        raise invalid if host == 'localhost' || host.end_with?('.localhost')

        port = uri.port
        port.nil? || port == 443 ? "https://#{host}" : "https://#{host}:#{port}"
      rescue Addressable::URI::InvalidURIError, TypeError
        raise invalid
      end

      def local
        raise Error.new('INVALID_LOCAL_ORIGIN', 400) unless Rails.configuration.x.use_https

        "https://#{Rails.configuration.x.web_domain.to_s.downcase.delete_suffix('.')}"
      end

      def local?(origin)
        Rails.configuration.x.use_https && origin == local
      end

      def invalid
        Error.new('INVALID_PROVIDER', 400)
      end
    end
  end
end
