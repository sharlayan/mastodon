# frozen_string_literal: true

class CleanupRemoteAvatarDecorationsWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 2

  CLEANUP_DELAY = 1.day

  class << self
    def enqueue(ids)
      ids = Array(ids).compact.uniq
      perform_in(CLEANUP_DELAY, ids) if ids.any?
    end
  end

  def perform(ids)
    AvatarDecoration.remote.where(id: ids).find_each do |decoration|
      next if Account.exists?(['avatar_decorations @> ?', [{ id: decoration.id }].to_json])

      decoration.destroy!
    end
  end
end
