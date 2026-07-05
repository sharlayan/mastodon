# frozen_string_literal: true

Fabricator(:antenna) do
  account { Fabricate.build(:account) }
  title 'MyAntenna'
end
