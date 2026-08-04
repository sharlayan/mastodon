# frozen_string_literal: true

class Sharlayan::FederationAggregationRunner
  include Lockable

  LOCK_NAME = 'sharlayan:federation_aggregation'
  LOCK_TIMEOUT = 1.day

  class << self
    def call(&block)
      new.call(&block)
    end
  end

  def call
    executed = false
    result = nil

    with_redis_lock(LOCK_NAME, autorelease: LOCK_TIMEOUT, raise_on_failure: false) do
      executed = true
      result = yield
    end

    executed ? result : 0
  end
end
