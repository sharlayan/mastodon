# frozen_string_literal: true

module Mastodon
  module Middleware
    class RoleplayFederationBlock
      FEDERATION_PATHS = [
        %r{\A/inbox/?\z},
        %r{\A/actor(/|\z)},
        %r{/inbox/?\z},
        %r{\A/\.well-known/webfinger/?\z},
        %r{\A/\.well-known/host-meta},
        %r{\A/\.well-known/nodeinfo/?\z},
        %r{\A/nodeinfo/},
      ].freeze

      ACTIVITYPUB_TYPES = %w(
        application/activity+json
        application/ld+json
      ).freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        return forbidden if enabled? && federation_request?(env)

        @app.call(env)
      end

      private

      def enabled?
        RoleplayModeHelper.roleplay_mode?
      end

      def federation_request?(env)
        path_federation?(env['PATH_INFO'].to_s) || header_federation?(env)
      end

      def path_federation?(path)
        FEDERATION_PATHS.any? { |pattern| pattern.match?(path) }
      end

      def header_federation?(env)
        accept = env['HTTP_ACCEPT'].to_s
        content_type = env['CONTENT_TYPE'].to_s

        ACTIVITYPUB_TYPES.any? { |type| accept.include?(type) || content_type.include?(type) }
      end

      def forbidden
        [403, { 'Content-Type' => 'application/json' }, ['{"error":"Federation is disabled on this server"}']]
      end
    end
  end
end
