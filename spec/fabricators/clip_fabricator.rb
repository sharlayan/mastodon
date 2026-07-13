# frozen_string_literal: true

Fabricator(:clip) do
  account
  title { sequence(:title) { |n| "Clip #{n}" } }
  public { true }
end
