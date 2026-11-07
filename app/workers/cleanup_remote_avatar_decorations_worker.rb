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
    decorations = AvatarDecoration.remote.where(id: ids).to_a
    return if decorations.empty?

    referenced = referenced_ids(decorations.map(&:id))
    decorations.each do |decoration|
      decoration.destroy! unless referenced.include?(decoration.id.to_s)
    end
  end

  private

  def referenced_ids(ids)
    Account
      .where('avatar_decorations @> ANY (ARRAY[?]::jsonb[])', ids.map { |id| [{ id: id }].to_json })
      .pluck(Arel.sql("jsonb_path_query_array(avatar_decorations, '$[*].id')"))
      .flatten
      .to_set(&:to_s)
  end
end
