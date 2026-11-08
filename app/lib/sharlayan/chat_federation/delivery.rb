# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Delivery
      RETRACTION_TYPES = %w(Delete Remove Undo).freeze

      class << self
        def call(actor:, conversation:, payload:, except_account_id: nil, except_domain: nil, include_pending_invitees: false, message: nil)
          seen = Set.new
          shared_json = payload.to_json unless message&.media_attachments&.any?
          remote = RETRACTION_TYPES.include?(payload['type']) ? ::Account.remote : ::Account.remote.without_suspended
          audience = remote.where(id: conversation.memberships.select(:account_id))
          audience = audience.or(remote.where(id: conversation.invitations.pending.select(:invitee_account_id))) if include_pending_invitees

          audience = audience.where.not(domain: except_domain) if except_domain.present?

          audience.where.not(id: except_account_id).find_each do |account|
            inbox = account.preferred_inbox_url
            next if inbox.blank? || seen.include?(inbox)

            seen << inbox
            ActivityPub::DeliveryWorker.perform_async(shared_json || Payload.for_domain(payload, message, account.domain).to_json, actor.id, inbox)
          end
        end
      end
    end
  end
end
