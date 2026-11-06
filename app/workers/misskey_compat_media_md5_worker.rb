# frozen_string_literal: true

class MisskeyCompatMediaMd5Worker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 0, lock: :until_executed, lock_ttl: 1.hour.to_i

  def perform(media_attachment_id)
    MisskeyCompat::MediaAttachmentMd5.for(MediaAttachment.find_by(id: media_attachment_id))
  end
end
