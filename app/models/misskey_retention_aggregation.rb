# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_retention_aggregations
#
#  id                 :bigint(8)        not null, primary key
#  cohort_account_ids :bigint(8)        default([]), not null, is an Array
#  data               :jsonb            not null
#  date_key           :string           not null
#  users_count        :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

class MisskeyRetentionAggregation < ApplicationRecord
  validates :date_key, presence: true, uniqueness: true

  scope :recent, -> { where(created_at: 31.days.ago..) }
end
