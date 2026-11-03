# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    # Ingress retries are bounded; a dependency delivered separately may arrive first.
    class DependencyNotReadyError < StandardError; end
  end
end
