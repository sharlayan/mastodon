# frozen_string_literal: true

Fabricator(:misskey_retention_aggregation) do
  date_key { sequence(:date_key) { |i| "2026-01-#{format('%02d', (i % 28) + 1)}" } }
  cohort_account_ids { [] }
  users_count 0
  data { {} }
end
