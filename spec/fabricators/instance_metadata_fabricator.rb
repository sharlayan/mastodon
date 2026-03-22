# frozen_string_literal: true

Fabricator(:instance_metadata) do
  domain { sequence(:domain) { |n| "instance#{n}.example.com" } }
end
