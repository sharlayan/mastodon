# frozen_string_literal: true

class Api::V1::Clips::FavouritesController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:index]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:index]

  before_action :require_user!
  before_action :set_clip, only: [:create]
  before_action :set_favouritable_clip, only: [:destroy]

  after_action :insert_pagination_headers, only: [:index]

  def index
    @clips = load_clips
    render json: @clips, each_serializer: REST::ClipSerializer, relationships: ClipRelationshipsPresenter.new(@clips, current_account.id)
  end

  def create
    current_account.clip_favourites.find_or_create_by!(clip: @clip)
    render json: @clip, serializer: REST::ClipSerializer
  rescue ActiveRecord::RecordNotUnique
    render json: @clip, serializer: REST::ClipSerializer
  end

  def destroy
    current_account.clip_favourites.where(clip_id: @clip.id).destroy_all
    render json: @clip, serializer: REST::ClipSerializer
  end

  private

  def require_feature_enabled!
    not_found unless Setting.clips_enabled
  end

  def set_clip
    @clip = Clip.find(params[:clip_id])
    not_found unless @clip.visible_to?(current_account)
  end

  def set_favouritable_clip
    @clip = Clip.find(params[:clip_id])
    return if @clip.visible_to?(current_account)

    not_found unless current_account.clip_favourites.exists?(clip_id: @clip.id)
  end

  def load_clips
    preload_collection(results.map(&:clip), Clip).select { |clip| clip.visible_to?(current_account) }
  end

  def results
    @results ||= current_account.clip_favourites.joins(:clip).eager_load(:clip).to_a_paginated_by_id(
      limit_param(DEFAULT_ACCOUNTS_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
  end

  def next_path
    favourites_api_v1_clips_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    favourites_api_v1_clips_url pagination_params(min_id: pagination_since_id) unless results.empty?
  end

  def pagination_collection
    results
  end

  def records_continue?
    results.size == limit_param(DEFAULT_ACCOUNTS_LIMIT)
  end
end
