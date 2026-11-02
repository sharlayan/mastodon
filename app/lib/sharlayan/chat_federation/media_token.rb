# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class MediaToken
      PURPOSE = :chat_media
      # Long enough for delivery retries, for receivers that link to the file instead of
      # caching it, and for refetching after a receiver's cache is vacuumed.
      TTL = 1.year

      class << self
        def generate(media_attachment)
          verifier.generate({ 'id' => media_attachment.id }, expires_in: TTL, purpose: PURPOSE)
        end

        def valid?(token, media_attachment)
          return false if token.blank?

          payload = verifier.verified(token, purpose: PURPOSE)
          payload.present? && payload['id'] == media_attachment.id
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
          false
        end

        private

        def verifier
          Rails.application.message_verifier('sharlayan_chat_media')
        end
      end
    end
  end
end
