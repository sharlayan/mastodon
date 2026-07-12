# frozen_string_literal: true

class ClipRelationshipsPresenter
  attr_reader :statuses_count_map, :favourites_count_map, :favourited_map

  def initialize(clips, current_account_id = nil)
    clip_ids = clips.map(&:id)

    @statuses_count_map   = ClipStatus.where(clip_id: clip_ids).group(:clip_id).count
    @favourites_count_map = ClipFavourite.where(clip_id: clip_ids).group(:clip_id).count
    @favourited_map       = if current_account_id.nil?
                              {}
                            else
                              ClipFavourite.where(clip_id: clip_ids, account_id: current_account_id).pluck(:clip_id).index_with(true)
                            end
  end
end
