# frozen_string_literal: true

module Sharlayan::Account::AvatarDecorations
  extend ActiveSupport::Concern

  included do
    before_destroy :remember_remote_avatar_decoration_ids
    after_destroy_commit :cleanup_remote_avatar_decorations
  end

  private

  def remember_remote_avatar_decoration_ids
    @remote_avatar_decoration_ids = avatar_decorations.filter_map { |config| config['id'] }
  end

  def cleanup_remote_avatar_decorations
    CleanupRemoteAvatarDecorationsWorker.enqueue(@remote_avatar_decoration_ids)
  end
end
