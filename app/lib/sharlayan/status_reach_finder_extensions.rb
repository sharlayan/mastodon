# frozen_string_literal: true

module Sharlayan::StatusReachFinderExtensions
  extend ActiveSupport::Concern

  def inboxes
    (super + private_mention_inboxes).uniq
  end

  private

  def reached_account_ids
    super - private_mentioned_account_ids
  end

  def followers_inboxes
    return super unless @status.private_visibility?

    individual_inboxes_for(followers_scope)
  end

  def private_mention_inboxes
    return [] unless @status.private_visibility?

    individual_inboxes_for(Account.where(id: private_mentioned_account_ids))
  end

  def private_mentioned_account_ids
    return [] unless @status.private_visibility?

    @private_mentioned_account_ids ||= @status.active_mentions.pluck(:account_id)
  end

  def individual_inboxes_for(scope)
    scope = scope.activitypub
    scope = scope.merge(Account.without_suspended) unless unsafe?

    DeliveryFailureTracker.without_unavailable(scope.where.not(inbox_url: [nil, '']).pluck(:inbox_url))
  end
end
