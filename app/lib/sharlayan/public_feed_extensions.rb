# frozen_string_literal: true

module Sharlayan::PublicFeedExtensions
  private

  def public_scope
    super.where.not(MisskeyChannelNote.linked_status_condition)
  end

  def account_filters_scope
    scope = super
    return scope unless MisskeyChannelMuting.active.exists?(account: account)

    scope.where.not(MisskeyChannelNote.muted_status_condition(account, Status.arel_table[:reblog_of_id]))
  end
end
