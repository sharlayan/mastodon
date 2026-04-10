# frozen_string_literal: true

Fabricator(:avatar_decoration_mute) do
  account        { Fabricate(:account) }
  target_account { Fabricate(:account) }
end
