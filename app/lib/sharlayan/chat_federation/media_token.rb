# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class MediaToken
      PURPOSE = :chat_media
      TTL = 24.hours

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
