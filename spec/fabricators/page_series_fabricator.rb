# frozen_string_literal: true

Fabricator(:page_series) do
  account
  title { sequence(:title) { |n| "Series #{n}" } }
end
