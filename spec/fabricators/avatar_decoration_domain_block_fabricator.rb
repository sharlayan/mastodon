# frozen_string_literal: true

Fabricator(:avatar_decoration_domain_block) do
  domain { sequence(:domain) { |i| "blocked#{i}.example.com" } }
end
