# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class MediaToken
      PURPOSE = :chat_media
      TTL = 1.year

      class << self
        # A token is for one server, and works for as long as that server has someone in the conversation.
        def generate(media_attachment, domain:)
          verifier.generate({ 'id' => media_attachment.id, 'domain' => domain }, expires_in: TTL, purpose: PURPOSE)
        end

        def valid?(token, media_attachment)
          return false if token.blank?

          payload = verifier.verified(token, purpose: PURPOSE)
          payload.present? && payload['id'] == media_attachment.id && member_on?(media_attachment, payload['domain'])
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
          false
        end

        private

        def member_on?(media_attachment, domain)
          return false if domain.blank?

          ChatMembership.joins(:account).exists?(
            chat_conversation_id: media_attachment.chat_messages.select(:chat_conversation_id),
            accounts: { domain: domain, suspended_at: nil }
          )
        end

        def verifier
          Rails.application.message_verifier('sharlayan_chat_media')
        end
      end
    end
  end
end
