# frozen_string_literal: true

class Api::V1::Clips::StatusesController < Api::BaseController
  include Api::ClipNotesRateLimit

  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:index]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:index]

  before_action :require_user!, except: [:index]
  before_action :set_clip
  before_action :require_ownership!, except: [:index]
  before_action :record_clip_notes_request!, only: [:index]

  after_action :insert_pagination_headers, only: [:index]

  def index
    @statuses = load_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  def create
    status = Status.find(status_params[:status_id])
    not_found unless StatusPolicy.new(current_account, status).show?

    @clip.with_lock do
      @clip.clip_statuses.find_or_create_by!(status_id: status.id)
    end
    render_empty
  end

  def destroy
    @clip.clip_statuses.where(status_id: params[:id]).destroy_all
    render_empty
  end

  private

  def require_feature_enabled!
    not_found unless Setting.clips_enabled
  end

  def set_clip
    @clip = Clip.find(params[:clip_id])
    not_found unless @clip.visible_to?(current_account)
  end

  def require_ownership!
    not_found unless @clip.account_id == current_account.id
  end

  def load_statuses
    preloaded = preload_collection(results.map(&:status), Status)
    preloaded.select { |status| StatusPolicy.new(current_account, status).show? }
  end

  def results
    @results ||= @clip.clip_statuses.joins(:status).eager_load(:status).to_a_paginated_by_id(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
  end

  def status_params
    params.permit(:status_id)
  end

  def next_path
    api_v1_clip_statuses_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_clip_statuses_url pagination_params(min_id: pagination_since_id) unless results.empty?
  end

  def pagination_collection
    results
  end

  def records_continue?
    results.size == limit_param(DEFAULT_STATUSES_LIMIT)
  end
end
