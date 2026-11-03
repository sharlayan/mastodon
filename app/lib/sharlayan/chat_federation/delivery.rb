# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Delivery
      class << self
        def call(actor:, conversation:, payload:, except_account_id: nil, except_domain: nil, include_pending_invitees: false)
          seen = Set.new
          json = payload.to_json
          audience = ::Account.remote.where(id: conversation.memberships.select(:account_id))
          audience = audience.or(::Account.remote.where(id: conversation.invitations.pending.select(:invitee_account_id))) if include_pending_invitees

          audience = audience.where.not(domain: except_domain) if except_domain.present?

          audience.where.not(id: except_account_id).find_each do |account|
            inbox = account.inbox_url
            next if inbox.blank? || seen.include?(inbox)

            seen << inbox
            ActivityPub::DeliveryWorker.perform_async(json, actor.id, inbox)
          end
        end
      end
    end
  end
end
