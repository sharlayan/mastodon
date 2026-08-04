# frozen_string_literal: true

class Sharlayan::FederationEdgeAggregator
  SNAPSHOT_SQL = <<~SQL.squish.freeze
    WITH signals AS (
      SELECT accounts.domain AS source_domain,
             reblogged_accounts.domain AS target_domain,
             'reblog' AS kind,
             statuses.created_at AS seen_at
      FROM statuses
      INNER JOIN accounts ON accounts.id = statuses.account_id
      INNER JOIN statuses reblogged_statuses ON reblogged_statuses.id = statuses.reblog_of_id
      INNER JOIN accounts reblogged_accounts ON reblogged_accounts.id = reblogged_statuses.account_id
      WHERE statuses.reblog_of_id IS NOT NULL
        AND statuses.deleted_at IS NULL

      UNION ALL

      SELECT accounts.domain AS source_domain,
             replied_accounts.domain AS target_domain,
             'reply' AS kind,
             statuses.created_at AS seen_at
      FROM statuses
      INNER JOIN accounts ON accounts.id = statuses.account_id
      INNER JOIN accounts replied_accounts ON replied_accounts.id = statuses.in_reply_to_account_id
      WHERE statuses.in_reply_to_account_id IS NOT NULL
        AND statuses.deleted_at IS NULL

      UNION ALL

      SELECT accounts.domain AS source_domain,
             quoted_accounts.domain AS target_domain,
             'quote' AS kind,
             quotes.created_at AS seen_at
      FROM quotes
      INNER JOIN accounts ON accounts.id = quotes.account_id
      INNER JOIN accounts quoted_accounts ON quoted_accounts.id = quotes.quoted_account_id
      WHERE quotes.quoted_account_id IS NOT NULL
        AND quotes.state = 1
    ), snapshot AS (
      SELECT source_domain,
             target_domain,
             COUNT(*) FILTER (WHERE kind = 'reblog') AS reblogs_count,
             COUNT(*) FILTER (WHERE kind = 'reply') AS replies_count,
             COUNT(*) FILTER (WHERE kind = 'quote') AS quotes_count,
             MIN(seen_at) AS first_seen_at,
             MAX(seen_at) AS last_seen_at
      FROM signals
      WHERE source_domain IS DISTINCT FROM target_domain
      GROUP BY source_domain, target_domain
    )
    INSERT INTO federation_instance_edges (
      source_domain,
      target_domain,
      reblogs_count,
      replies_count,
      quotes_count,
      first_seen_at,
      last_seen_at,
      created_at,
      updated_at
    )
    SELECT source_domain,
           target_domain,
           reblogs_count,
           replies_count,
           quotes_count,
           first_seen_at,
           last_seen_at,
           :started_at,
           :started_at
    FROM snapshot
    ON CONFLICT (source_domain, target_domain) DO UPDATE SET
      reblogs_count = excluded.reblogs_count,
      replies_count = excluded.replies_count,
      quotes_count = excluded.quotes_count,
      first_seen_at = excluded.first_seen_at,
      last_seen_at = excluded.last_seen_at,
      updated_at = excluded.updated_at
  SQL

  class << self
    def enabled?
      return false if RoleplayModeHelper.roleplay_mode?

      Setting.federation_instance_edges_enabled
    end

    def call(started_at: Time.now.utc)
      return 0 unless enabled?

      ActiveSupport::Notifications.instrument('federation_edge_snapshot.sharlayan') do |payload|
        result = Sharlayan::FederationAggregationRunner.call { FederationInstanceEdge.replace_all_from_sql!(SNAPSHOT_SQL, started_at:) }
        payload[:affected_rows] = result
        result
      end
    end
  end
end
