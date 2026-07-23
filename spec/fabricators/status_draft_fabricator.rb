# frozen_string_literal: true

Fabricator(:status_draft) do
  account
  data { { status: 'Saved draft', visibility: 'public' } }
end
