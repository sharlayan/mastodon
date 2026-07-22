# frozen_string_literal: true

RSpec::Matchers.define :have_loaded_association do |association|
  match do |record|
    record.association(association).loaded?
  end

  failure_message do |record|
    "expected #{record} to have loaded association #{association} but it did not."
  end
end
