# frozen_string_literal: true

Fabricator(:page) do
  account
  title { sequence(:title) { |n| "Page #{n}" } }
  name { sequence(:name) { |n| "page-#{n}" } }
  content { [] }
end
