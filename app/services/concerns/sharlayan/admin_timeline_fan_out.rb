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
        if update? && Sharlayan::AdminTimeline.owner_conversation?(status)
          Sharlayan::AdminTimeline.follower_redis_channels_for(status, include_owner_conversation: true).each do |channel|
            redis.publish(channel, { event: :delete, payload: status.id.to_s }.to_json)
          end
        end
      end
    end
  end

  module Remove
    def call(status, **options)
      channels = Sharlayan::AdminTimeline.removal_redis_channels_for(status) if status.account.local? && !options[:skip_streaming]

      super.tap do
        channels&.each { |channel| redis.publish(channel, @payload) }
      end
    end
  end
end
