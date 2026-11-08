# frozen_string_literal: true

class ChatMediaRemovalWorker
  include Sidekiq::Worker

  BATCH_SIZE = 100
  INLINE_LIMIT = 20

  sidekiq_options queue: 'default', retry: 3

  def self.remove(media_attachment_ids)
    if media_attachment_ids.size > INLINE_LIMIT
      media_attachment_ids.each_slice(BATCH_SIZE) { |batch| perform_async(batch) }
    else
      new.perform(media_attachment_ids)
    end
  end

  def perform(media_attachment_ids)
    MediaAttachment.unattached.where(id: media_attachment_ids).find_each(&:destroy!)
  end
end
