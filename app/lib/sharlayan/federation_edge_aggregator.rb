# frozen_string_literal: true

class Sharlayan::FederationEdgeAggregator
  Edge = Struct.new(:reblogs_count, :replies_count, :quotes_count, :first_seen_at, :last_seen_at) do
    def observe(column, count, first_seen_at, last_seen_at)
      self[column] += count
      self.first_seen_at = [self.first_seen_at, first_seen_at].compact.min
      self.last_seen_at = [self.last_seen_at, last_seen_at].compact.max
    end
  end

  class << self
    def enabled?
      return false if RoleplayModeHelper.roleplay_mode?

      Setting.federation_instance_edges_enabled
    end

    def call(started_at: Time.now.utc)
      return 0 unless enabled?

      Sharlayan::FederationAggregationRunner.call { new(started_at).call }
    end
  end

  def initialize(started_at)
    @started_at = started_at
    @edges = Hash.new { |hash, key| hash[key] = Edge.new(0, 0, 0, nil, nil) }
  end

  def call
    collect(reblog_scope, :reblogs_count)
    collect(reply_scope, :replies_count)
    collect(quote_scope, :quotes_count)

    FederationInstanceEdge.replace_all!(rows, started_at: @started_at)
    @edges.size
  end

  private

  def collect(scope, column)
    scope.each do |source_domain, target_domain, count, first_seen_at, last_seen_at|
      next if source_domain == target_domain

      @edges[[source_domain, target_domain]].observe(column, count, first_seen_at, last_seen_at)
    end
  end

  def reblog_scope
    grouped(
      Status.reorder(nil)
        .joins(:account)
        .joins('INNER JOIN statuses reblogged_statuses ON reblogged_statuses.id = statuses.reblog_of_id')
        .joins('INNER JOIN accounts reblogged_accounts ON reblogged_accounts.id = reblogged_statuses.account_id')
        .where.not(reblog_of_id: nil),
      Arel.sql('accounts.domain'),
      Arel.sql('reblogged_accounts.domain'),
      Arel.sql('statuses.created_at')
    )
  end

  def reply_scope
    grouped(
      Status.reorder(nil)
        .joins(:account)
        .joins('INNER JOIN accounts replied_accounts ON replied_accounts.id = statuses.in_reply_to_account_id')
        .where.not(in_reply_to_account_id: nil),
      Arel.sql('accounts.domain'),
      Arel.sql('replied_accounts.domain'),
      Arel.sql('statuses.created_at')
    )
  end

  def quote_scope
    grouped(
      Quote.accepted
        .joins(:account)
        .joins('INNER JOIN accounts quoted_accounts ON quoted_accounts.id = quotes.quoted_account_id')
        .where.not(quoted_account_id: nil),
      Arel.sql('accounts.domain'),
      Arel.sql('quoted_accounts.domain'),
      Arel.sql('quotes.created_at')
    )
  end

  def grouped(scope, source_column, target_column, timestamp_column)
    scope.group(source_column, target_column).pluck(
      source_column,
      target_column,
      Arel.star.count,
      timestamp_column.minimum,
      timestamp_column.maximum
    )
  end

  def rows
    @edges.map do |(source_domain, target_domain), edge|
      {
        source_domain: source_domain,
        target_domain: target_domain,
        reblogs_count: edge.reblogs_count,
        replies_count: edge.replies_count,
        quotes_count: edge.quotes_count,
        first_seen_at: edge.first_seen_at,
        last_seen_at: edge.last_seen_at,
        created_at: @started_at,
        updated_at: @started_at,
      }
    end
  end
end
