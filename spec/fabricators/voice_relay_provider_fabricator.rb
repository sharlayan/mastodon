# frozen_string_literal: true

Fabricator(:voice_relay_provider) do
  origin { sequence(:voice_relay_origin) { |i| "https://voice#{i}.example.org" } }
  secret { "relay-secret-#{'x' * 32}" }
end
