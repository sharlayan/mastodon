# frozen_string_literal: true

class MisskeyCompat::PageCollectionContext
  def self.for(pages, current_account: nil)
    new(pages, current_account: current_account)
  end

  def initialize(pages, current_account: nil)
    @pages = Array(pages).compact
    @current_account = current_account
    @attached_media_ids = @pages.to_h { |page| [page.id, page.renderable_attached_media_ids.to_set(&:to_s)] }
    preload_attached_media
    preload_likes
  end

  def attached_media_for(page)
    @attached_media.fetch(page.id, [])
  end

  def liked_by_current_account?(page)
    @liked_page_ids.key?(page.id)
  end

  private

  def preload_attached_media
    media_ids = @attached_media_ids.values.flat_map(&:to_a).uniq
    @attached_media = @pages.to_h { |page| [page.id, []] }
    return if media_ids.empty?

    media_by_account = MediaAttachment.where(id: media_ids, account_id: @pages.map(&:account_id).uniq)
      .includes(drive_file: :custom_name)
      .to_a
      .group_by(&:account_id)
    @pages.each do |page|
      @attached_media[page.id] = media_by_account.fetch(page.account_id, []).select { |media| media.account_id == page.account_id && @attached_media_ids[page.id].include?(media.id.to_s) }
    end
  end

  def preload_likes
    @liked_page_ids = if @current_account
                        PageLike.where(page_id: @pages.map(&:id), account_id: @current_account.id).pluck(:page_id).index_with(true)
                      else
                        {}
                      end
  end
end
