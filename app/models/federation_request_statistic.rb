# frozen_string_literal: true

# == Schema Information
#
# Table name: federation_request_statistics
#
#  id                      :bigint(8)        not null, primary key
#  bucket_at               :datetime         not null
#  deliver_failed_count    :bigint(8)        default(0), not null
#  deliver_succeeded_count :bigint(8)        default(0), not null
#  domain                  :string           not null
#  inbox_received_count    :bigint(8)        default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#

class FederationRequestStatistic < ApplicationRecord
  COUNTER_COLUMNS = %i(deliver_succeeded_count deliver_failed_count inbox_received_count).freeze
  RETENTION_PERIOD = 500.days

  validates :domain, presence: true
  validates :bucket_at, presence: true

  scope :in_bucket_range, ->(range) { where(bucket_at: range) }
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :expired, -> { where(bucket_at: ...RETENTION_PERIOD.ago.utc.beginning_of_hour) }

  def self.accumulate!(rows)
    return if rows.empty?

    now = Time.now.utc

    upsert_all(
      rows.map { |row| row.merge(created_at: now, updated_at: now) },
      unique_by: %i(domain bucket_at),
      on_duplicate: Arel.sql(<<~SQL.squish)
        deliver_succeeded_count = federation_request_statistics.deliver_succeeded_count + excluded.deliver_succeeded_count,
        deliver_failed_count = federation_request_statistics.deliver_failed_count + excluded.deliver_failed_count,
        inbox_received_count = federation_request_statistics.inbox_received_count + excluded.inbox_received_count,
        updated_at = excluded.updated_at
      SQL
    )
  end
end
