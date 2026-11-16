# frozen_string_literal: true

class MisskeyCompatOrphanedMediaCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: false, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform
    Vacuum::MediaAttachmentsVacuum.new(nil).perform
  end
end
