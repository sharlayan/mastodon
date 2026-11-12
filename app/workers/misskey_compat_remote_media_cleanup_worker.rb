# frozen_string_literal: true

class MisskeyCompatRemoteMediaCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: false, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform(domain = nil)
    scope = MediaAttachment.cached
    scope = scope.joins(:account).where(accounts: { domain: domain }) if domain.present?

    scope.find_in_batches do |media_attachments|
      AttachmentBatch.new(MediaAttachment, media_attachments).clear
    rescue => e
      Rails.logger.error("Skipping batch while clearing Misskey-compat remote media cache: #{e}")
    end
  end
end
