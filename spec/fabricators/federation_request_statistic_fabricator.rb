# frozen_string_literal: true

Fabricator(:federation_request_statistic) do
  domain { sequence(:domain) { |i| "remote-#{i}.example" } }
  bucket_at { Time.now.utc.beginning_of_hour }
end
