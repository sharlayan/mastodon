# frozen_string_literal: true

module Sharlayan::AdminTimelineFanOut
  module FanOut
    def call(status, options = {})
      super.tap do
        redis.publish('timeline:admin', anonymous_payload) if status.account.local? && !status.proper.account.suspended?
      end
    end
  end

  module Remove
    def call(status, **options)
      super.tap do
        redis.publish('timeline:admin', @payload) if status.account.local? && !options[:skip_streaming]
      end
    end
  end
end
