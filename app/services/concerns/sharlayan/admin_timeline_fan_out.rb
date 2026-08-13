# frozen_string_literal: true

module Sharlayan::AdminTimelineFanOut
  module FanOut
    def call(status, options = {})
      super.tap do
        next unless status.account.local? && !status.proper.account.suspended?
        next unless status.admin_timeline_eligible?

        channels = Sharlayan::AdminTimeline.redis_channels_for(status)
        channels.each { |channel| redis.publish(channel, anonymous_payload) }

        redis.publish(Sharlayan::AdminTimeline::REDIS_CHANNEL, { event: :delete, payload: status.id.to_s }.to_json) if update? && channels.exclude?(Sharlayan::AdminTimeline::REDIS_CHANNEL)
      end
    end
  end

  module Remove
    def call(status, **options)
      channels = Sharlayan::AdminTimeline::REMOVAL_REDIS_CHANNELS if status.account.local? && !options[:skip_streaming]

      super.tap do
        channels&.each { |channel| redis.publish(channel, @payload) }
      end
    end
  end
end
