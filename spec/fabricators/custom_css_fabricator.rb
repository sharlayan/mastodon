# frozen_string_literal: true

Fabricator(:custom_css) do
  user
  css '.status { color: red; }'
end
