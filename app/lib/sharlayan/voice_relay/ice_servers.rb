# frozen_string_literal: true

module Sharlayan
  module VoiceRelay
    module IceServers
      MAX_SERVERS = 4
      MAX_URLS = 8
      MAX_CREDENTIAL_LENGTH = 512
      BLOCKED_PORT = 53
      CREDENTIAL_KEYS = %w(username credential).freeze
      URL_PATTERN = /\A(stun|turns?):[\x21-\x7e]{1,256}\z/
      TURN_PATTERN = /\Aturns?:/
      PORT_PATTERN = /\A\d{1,5}\z/
      HOST_NAME = /\A[a-z0-9-]+(?:\.[a-z0-9-]+)*\.?\z/
      NUMERIC_LABEL = /\A(?:\d+|0x[0-9a-f]*)\z/
      BRACKETED_IPV6 = /\A\[[0-9a-f:.]+\]\z/
      IPV4_OCTET = /(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)/
      DOTTED_IPV4 = /\A#{IPV4_OCTET}(?:\.#{IPV4_OCTET}){3}\z/
      LOCAL_NAME_SUFFIXES = %w(localhost local internal home.arpa).freeze
      LOCAL_HOST_NAMES = %w(localhost.localdomain).freeze
      LOCAL_IPV4_RANGES = %w(
        0.0.0.0/8 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16
        255.255.255.255/32 224.0.0.0/4 198.18.0.0/15
      ).map { |range| IPAddr.new(range) }.freeze
      LOCAL_IPV6_RANGES = %w(
        ::/128 ::1/128 fc00::/7 fe80::/10 fec0::/10 ff00::/8 ::ffff:0:0:0/96 2001:2::/48
      ).map { |range| IPAddr.new(range) }.freeze
      LOCAL_USE_NAT64_LAYOUTS = [
        { ipv4: [6, 7, 9, 10], zero: [8, 11, 12, 13, 14, 15] },
        { ipv4: [7, 9, 10, 11], zero: [8, 12, 13, 14, 15] },
        { ipv4: [9, 10, 11, 12], zero: [8, 13, 14, 15] },
        { ipv4: [12, 13, 14, 15], zero: [] },
      ].freeze

      module_function

      def parse(value)
        return nil unless value.is_a?(Array) && value.size.between?(1, MAX_SERVERS)

        servers = value.map { |entry| server(entry) }
        servers.all? ? servers : nil
      end

      def server(entry)
        return nil unless entry.is_a?(Hash)

        urls = entry['urls']
        return nil unless urls.is_a?(Array) && urls.size.between?(1, MAX_URLS) && urls.all? { |url| allowed_url?(url) }
        return nil unless CREDENTIAL_KEYS.all? { |key| !entry.key?(key) || (entry[key].is_a?(String) && entry[key].length <= MAX_CREDENTIAL_LENGTH) }
        return nil if urls.any? { |url| TURN_PATTERN.match?(url) } && CREDENTIAL_KEYS.any? { |key| entry[key].to_s.empty? }

        CREDENTIAL_KEYS.each_with_object({ urls: urls.dup }) do |key, result|
          result[key.to_sym] = entry[key] if entry.key?(key)
        end
      end

      def allowed_url?(url)
        return false unless url.is_a?(String) && URL_PATTERN.match?(url)

        host, port = host_and_port(url)
        !host.nil? && port != BLOCKED_PORT && !local_host?(host)
      end

      def host_and_port(url)
        host_port = url[(url.index(':') + 1)..].split('?', 2).first.to_s.downcase

        if host_port.start_with?('[')
          close = host_port.index(']')
          return nil if close.nil?

          host = host_port[..close]
          after = host_port[(close + 1)..]
          return nil unless after.empty? || after.start_with?(':')

          port = after.empty? ? nil : after[1..]
        else
          host, port = host_port.split(':', 2)
          host = host.to_s
        end

        return [host, nil] if port.nil?
        return nil unless PORT_PATTERN.match?(port) && port.to_i.between?(1, 65_535)

        [host, port.to_i]
      end

      def local_host?(host)
        return local_bracketed_host?(host) if host.start_with?('[')
        return true unless HOST_NAME.match?(host)

        name = host.delete_suffix('.')
        labels = name.split('.')
        return !DOTTED_IPV4.match?(host) || local_ipv4?(IPAddr.new(host)) if NUMERIC_LABEL.match?(labels.last)
        return true if labels.size == 1 || LOCAL_HOST_NAMES.include?(name)

        LOCAL_NAME_SUFFIXES.any? { |suffix| name == suffix || name.end_with?(".#{suffix}") }
      end

      def local_bracketed_host?(host)
        return true unless BRACKETED_IPV6.match?(host)

        address = IPAddr.new(host[1...-1])
        !address.ipv6? || local_ipv6?(address)
      rescue IPAddr::Error
        true
      end

      def local_ipv4?(address)
        LOCAL_IPV4_RANGES.any? { |range| range.include?(address) }
      end

      def local_ipv6?(address)
        bytes = address.hton.bytes
        parts = bytes.each_slice(2).map { |high, low| (high << 8) | low }
        ipv4_at = ->(indexes) { IPAddr.new_ntoh(indexes.map { |index| bytes[index] }.pack('C*')) }

        return local_ipv4?(ipv4_at.call([12, 13, 14, 15])) if parts.first(5).all?(&:zero?) && parts[5] == 0xffff
        return true if parts.first(6).all?(&:zero?)

        if parts[0] == 0x64 && parts[1] == 0xff9b
          return local_ipv4?(ipv4_at.call([12, 13, 14, 15])) if parts[2..5].all?(&:zero?)

          if parts[2] == 0x0001
            layouts = LOCAL_USE_NAT64_LAYOUTS.select { |layout| layout[:zero].all? { |index| bytes[index].zero? } }
            return layouts.any? { |layout| local_ipv4?(ipv4_at.call(layout[:ipv4])) }
          end
        end

        return local_ipv4?(ipv4_at.call([2, 3, 4, 5])) if parts[0] == 0x2002

        LOCAL_IPV6_RANGES.any? { |range| range.include?(address) }
      end
    end
  end
end
