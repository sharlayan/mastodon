# frozen_string_literal: true

module Sharlayan::Status::MediaLimits
  extend ActiveSupport::Concern

  class_methods do
    def remote_media_attachments_limit
      Setting.remote_media_attachments_limit
    end
  end

  def sharlayan_media_attachments_limit
    local? ? ::Status::MEDIA_ATTACHMENTS_LIMIT : self.class.remote_media_attachments_limit
  end
end
