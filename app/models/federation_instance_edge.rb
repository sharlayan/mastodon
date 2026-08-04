# frozen_string_literal: true

# == Schema Information
#
# Table name: federation_instance_edges
#
#  id            :bigint(8)        not null, primary key
#  first_seen_at :datetime
#  last_seen_at  :datetime
#  quotes_count  :bigint(8)        default(0), not null
#  reblogs_count :bigint(8)        default(0), not null
#  replies_count :bigint(8)        default(0), not null
#  source_domain :string
#  target_domain :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class FederationInstanceEdge < ApplicationRecord
  COUNTER_COLUMNS = %i(reblogs_count replies_count quotes_count).freeze
  SNAPSHOT_STATEMENT_TIMEOUT_SQL = 'SET LOCAL statement_timeout = 900000'
  SNAPSHOT_LOCK_TIMEOUT_SQL = 'SET LOCAL lock_timeout = 5000'

  scope :involving_local, -> { where(source_domain: nil).or(where(target_domain: nil)) }
  scope :between_remotes, -> { where.not(source_domain: nil).where.not(target_domain: nil) }
  scope :outbound_from, ->(domain) { where(source_domain: domain) }
  scope :inbound_to, ->(domain) { where(target_domain: domain) }
  scope :touching, ->(domain) { where(source_domain: domain).or(where(target_domain: domain)) }

  def self.replace_all_from_sql!(snapshot_sql, started_at:)
    transaction do
      connection.execute(SNAPSHOT_STATEMENT_TIMEOUT_SQL)
      connection.execute(SNAPSHOT_LOCK_TIMEOUT_SQL)

      statement = sanitize_sql_array([snapshot_sql, { started_at: }])
      affected_rows = connection.update(statement, "#{name} Snapshot")

      where(updated_at: ...started_at).delete_all
      affected_rows
    end
  end

  def interactions_count
    COUNTER_COLUMNS.sum { |column| self[column] }
  end

  def local_source?
    source_domain.nil?
  end

  def local_target?
    target_domain.nil?
  end
end
