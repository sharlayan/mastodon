# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class MediaToken
      PURPOSE = :chat_media

      class << self
        # A token is for one server, and works for as long as that server has someone in the conversation. It has no
        # time limit, as a server that keeps no copy of remote files fetches one each time it is shown.
        def generate(media_attachment, domain:)
          verifier.generate({ 'id' => media_attachment.id, 'domain' => domain }, purpose: PURPOSE)
        end

        def valid?(token, media_attachment)
          return false unless token.is_a?(String) && token.present?

          payload = verifier.verified(token, purpose: PURPOSE)
          payload.present? && payload['id'] == media_attachment.id && !media_attachment.account.suspended? && member_on?(media_attachment, payload['domain'])
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
          false
        end

        # Only proves that this server signed it for this attachment, without asking the database who may see it.
        def signed_for?(token, media_id)
          token.is_a?(String) && verifier.verified(token, purpose: PURPOSE)&.dig('id').to_s == media_id.to_s
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
