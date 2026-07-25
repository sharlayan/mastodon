# frozen_string_literal: true

Fabricator(:misskey_federation_instance_stat) do
  domain { sequence(:domain) { |i| "instance-#{i}.example" } }
  first_retrieved_at { Time.zone.now }
  users_count 0
  notes_count 0
  following_count 0
  followers_count 0
end
