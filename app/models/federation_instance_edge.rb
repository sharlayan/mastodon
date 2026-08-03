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

  scope :involving_local, -> { where(source_domain: nil).or(where(target_domain: nil)) }
  scope :between_remotes, -> { where.not(source_domain: nil).where.not(target_domain: nil) }
  scope :outbound_from, ->(domain) { where(source_domain: domain) }
  scope :inbound_to, ->(domain) { where(target_domain: domain) }
  scope :touching, ->(domain) { where(source_domain: domain).or(where(target_domain: domain)) }

  def self.replace_all!(rows, started_at:)
    transaction do
      rows.each_slice(1_000) do |slice|
        upsert_all(
          slice,
          unique_by: %i(source_domain target_domain),
          on_duplicate: Arel.sql(<<~SQL.squish)
            reblogs_count = excluded.reblogs_count,
            replies_count = excluded.replies_count,
            quotes_count = excluded.quotes_count,
            first_seen_at = excluded.first_seen_at,
            last_seen_at = excluded.last_seen_at,
            updated_at = excluded.updated_at
          SQL
        )
      end

      where(updated_at: ...started_at).delete_all
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
