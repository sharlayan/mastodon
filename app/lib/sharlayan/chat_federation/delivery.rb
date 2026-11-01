# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Delivery
      class << self
        def call(actor:, conversation:, payload:, except_account_id: nil)
          seen = Set.new

          conversation.accounts.remote.where.not(id: except_account_id).find_each do |account|
            inbox = account.inbox_url
            next if inbox.blank? || seen.include?(inbox)

            seen << inbox
            ActivityPub::DeliveryWorker.perform_async(payload.to_json, actor.id, inbox)
          end
        end
      end
    end
  end
end