# frozen_string_literal: true

module Sharlayan::Status::MediaLimits
  extend ActiveSupport::Concern

  MIN_REMOTE_MEDIA_ATTACHMENTS_LIMIT = 4
  MAX_MEDIA_ATTACHMENTS_LIMIT = 16
  REMOTE_MEDIA_ATTACHMENTS_LIMIT_RANGE = (MIN_REMOTE_MEDIA_ATTACHMENTS_LIMIT..MAX_MEDIA_ATTACHMENTS_LIMIT)
  DEFAULT_LOCAL_MEDIA_ATTACHMENTS_LIMIT = 10
  LOCAL_MEDIA_ATTACHMENTS_LIMIT_RANGE = (1..MAX_MEDIA_ATTACHMENTS_LIMIT)

  def self.default_local_media_attachments_limit(env = ENV)
    configured = Integer(env.fetch('MAX_MEDIA_ATTACHMENTS', ''), exception: false)
    (configured || DEFAULT_LOCAL_MEDIA_ATTACHMENTS_LIMIT).clamp(LOCAL_MEDIA_ATTACHMENTS_LIMIT_RANGE)
  end

  class_methods do
    def local_media_attachments_limit
      Setting.local_media_attachments_limit.to_i.clamp(1, ::Status::MEDIA_ATTACHMENTS_LIMIT)
    end

    def remote_media_attachments_limit
      Setting.remote_media_attachments_limit
    end
  end

  def sharlayan_media_attachments_limit
    local? ? ::Status::MEDIA_ATTACHMENTS_LIMIT : self.class.remote_media_attachments_limit
  end
end
