# frozen_string_literal: true

module Sharlayan::DeleteAccountServiceExtensions
  private

  def purge_media_attachments!
    purge_pages!
    super
    purge_drive!
  end

  def purge_bookmarks!
    purge_status_reactions!
    super
  end

  def purge_pages!
    @account.page_likes.in_batches.delete_all
    @account.pages.in_batches.destroy_all
  end

  def purge_drive!
    @account.drive_files.in_batches.destroy_all
    @account.drive_folders.in_batches.destroy_all
  end

  def purge_status_reactions!
    @account.status_reactions.in_batches do |status_reactions|
      ids = status_reactions.pluck(:status_id)
      StatusStat.where(status_id: ids).update_all('reactions_count = GREATEST(0, reactions_count - 1)')
      Chewy.strategy.current.update(StatusesIndex, ids) if Chewy.enabled?
      Rails.cache.delete_multi(ids.map { |id| "statuses/#{id}" })
      status_reactions.delete_all
    end
  end
end
