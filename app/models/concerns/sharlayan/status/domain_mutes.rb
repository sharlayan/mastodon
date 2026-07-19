# frozen_string_literal: true

module Sharlayan::Status::DomainMutes
  extend ActiveSupport::Concern

  included do
    scope :not_domain_muted_by_account, lambda { |account|
      return self if account.muted_from_timeline_domains.blank?

      followed_account_ids = Follow.where(account_id: account.id).select(:target_account_id)

      left_outer_joins(:account)
        .where('accounts.domain is NULL or statuses.account_id in (?) or accounts.domain not in (?)',
               followed_account_ids,
               account.muted_from_timeline_domains)
        .where(<<~SQL.squish, followed_account_ids, account.muted_from_timeline_domains)
          statuses.reblog_of_id IS NULL OR NOT EXISTS (
            SELECT 1
            FROM statuses reblogged_statuses
            INNER JOIN accounts reblogged_accounts ON reblogged_accounts.id = reblogged_statuses.account_id
            WHERE reblogged_statuses.id = statuses.reblog_of_id
              AND reblogged_statuses.account_id NOT IN (?)
              AND reblogged_accounts.domain IN (?)
          )
        SQL
    }
  end
end
