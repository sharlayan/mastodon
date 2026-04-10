# frozen_string_literal: true

Fabricator(:avatar_decoration) do
  name     { sequence(:name) { |i| "decoration_#{i}" } }
  approved { true }
  host     nil
  image    { Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').open }
end
