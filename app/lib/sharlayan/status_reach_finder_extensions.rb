# frozen_string_literal: true

module Sharlayan::StatusReachFinderExtensions
  extend ActiveSupport::Concern

  def inboxes
    (super + private_mention_inboxes + hidden_reply_recipient_inboxes).uniq
  end

  private

  def reached_account_ids
    return listed_reply_recipient_ids if limited_reply?

    super - private_mentioned_account_ids
  end

  def followers_inboxes
    return super unless @status.private_visibility?

    individual_inboxes_for(followers_scope)
  end

  def limited_reply?
    @status.limited_visibility? && @status.limited_reply?
  end

  def listed_reply_recipient_ids
    @listed_reply_recipient_ids ||= Sharlayan::LimitedReplyScope.listed_account_ids(@status)
  end

  def hidden_reply_recipient_inboxes
    return [] unless limited_reply?

    individual_inboxes_for(Account.where(id: mentioned_account_ids - listed_reply_recipient_ids))
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
