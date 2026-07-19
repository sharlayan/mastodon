# frozen_string_literal: true

module Sharlayan::AdminTimelineFanOut
  extend ActiveSupport::Concern

  included do
    include RoleplayModeHelper
  end

  private

  def broadcast_to_admin_stream!
    return unless roleplay_mode? && @status.account.local?

    redis.publish('timeline:admin', anonymous_payload)
  end

  def remove_from_admin
    return unless roleplay_mode? && @account.local?
    return if skip_streaming?

    redis.publish('timeline:admin', @payload)
  end
end
