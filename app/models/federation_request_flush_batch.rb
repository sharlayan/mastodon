# frozen_string_literal: true

# == Schema Information
#
# Table name: federation_request_flush_batches
#
#  id         :bigint(8)        not null, primary key
#  batch_key  :string           not null
#  created_at :datetime         not null
#

class FederationRequestFlushBatch < ApplicationRecord
  RETENTION_PERIOD = 30.days

  scope :expired, -> { where(created_at: ...RETENTION_PERIOD.ago) }

  def self.claim!(batch_key)
    insert_all([{ batch_key: batch_key, created_at: Time.now.utc }], unique_by: :batch_key, returning: %w(id)).rows.any?
  end
end
