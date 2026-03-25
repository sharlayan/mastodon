# frozen_string_literal: true

Fabricator(:account_switch_authorization) do
  account        { Fabricate(:account) }
  target_account { Fabricate(:account) }
  push_forward   false
end
