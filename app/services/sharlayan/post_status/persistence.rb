# frozen_string_literal: true

module Sharlayan::PostStatus
  class Persistence
    def initialize(account:, options:, circle:)
      @account = account
      @options = options
      @circle = circle
    end

    def process_mentions!(status, service, attributes:)
      status.assign_attributes(attributes)
      service.call(status, circle: @circle)
      status.limited_scope = :personal if @circle.present? && status.mentions.empty?
    end

    def persist_status!(status, media:)
      ApplicationRecord.transaction do
        DriveFile.lock_for_media_attachments(media)
        yield
        @circle.statuses << status if @circle.present?
        attach_clips!(status)
      end
    end

    def persist_scheduled!(media:)
      ApplicationRecord.transaction do
        DriveFile.lock_for_media_attachments(media)
        yield
      end
    end

    private

    def attach_clips!(status)
      return unless Setting.clips_enabled
      return if @options[:clip_ids].blank?

      @account.clips.where(id: @options[:clip_ids]).find_each do |clip|
        clip.with_lock do
          next if clip.clip_statuses.count >= Clip::STATUSES_LIMIT

          clip.statuses << status
        end
      end
    end
  end
end
