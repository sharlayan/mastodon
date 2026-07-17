# frozen_string_literal: true

module Sharlayan::Status::MediaLimits
  REMOTE_MEDIA_ATTACHMENTS_LIMIT = 16

  def sharlayan_media_attachments_limit
    local? ? ::Status::MEDIA_ATTACHMENTS_LIMIT : REMOTE_MEDIA_ATTACHMENTS_LIMIT
  end
end
