# frozen_string_literal: true

module Sharlayan::DeleteAccountServiceExtensions
  PURGED_ASSOCIATIONS_WITHOUT_SIDE_EFFECTS = %w(
    reaction_mutes
    avatar_decoration_mutes
    favorite_emojis
    status_read_receipts
    page_daily_statistics
    misskey_registry_items
  ).freeze

  PURGED_ASSOCIATIONS = (%w(
    status_drafts
    domain_mutes
    custom_emoji_mutes
    page_series
  ) + PURGED_ASSOCIATIONS_WITHOUT_SIDE_EFFECTS).freeze

  private

  def associations_for_destruction
    super + PURGED_ASSOCIATIONS
  end

  def purge_association(association_name)
    return @account.public_send(association_name).in_batches.delete_all if PURGED_ASSOCIATIONS_WITHOUT_SIDE_EFFECTS.include?(association_name)

    super
  end

  def purge_media_attachments!
    purge_pages!
    super
    purge_drive!
  end

  def purge_user!
    user_id = @account.user&.id if @account.local?
    super
    LocalSettingsStore.delete(user_id) if user_id
  end

  def purge_bookmarks!
    purge_status_reactions!
    super
  end

  def purge_pages!
    @account.page_likes.in_batches do |page_likes|
      Page.where(id: page_likes.pluck(:page_id)).update_all('likes_count = GREATEST(0, likes_count - 1)')
      page_likes.delete_all
    end
    @account.pages.in_batches.destroy_all
  end

  def purge_drive!
    @account.drive_files.in_batches.destroy_all
    @account.drive_folders.in_batches.destroy_all
  end

  def purge_status_reactions!
    @account.status_reactions.in_batches do |status_reactions|
      ids = status_reactions.distinct.pluck(:status_id)
      reaction_count = status_reactions
        .where(StatusReaction.arel_table[:status_id].eq(StatusStat.arel_table[:status_id]))
        .reorder(nil)
        .select('COUNT(*)')
      StatusStat.where(status_id: ids).update_all("reactions_count = GREATEST(0, reactions_count - (#{reaction_count.to_sql}))")
      status_reactions.delete_all
      Chewy.strategy.current.update(StatusesIndex, ids) if Chewy.enabled?
      Rails.cache.delete_multi(ids.flat_map { |id| ["v3:statuses/#{id}", "statuses/show:v3:statuses/#{id}", StatusReaction.summary_cache_key(id)] })
    end
  end
end
