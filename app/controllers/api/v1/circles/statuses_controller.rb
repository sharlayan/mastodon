# frozen_string_literal: true

class Api::V1::Circles::StatusesController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }
  before_action :require_user!
  before_action :set_circle

  after_action :insert_pagination_headers

  def index
    @statuses = load_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  private

  def require_feature_enabled!
    not_found unless Setting.circles_enabled
  end

  def set_circle
    @circle = Circle.where(account: current_account).find(params[:circle_id])
  end

  def load_statuses
    preload_collection(results.map(&:status), Status)
  end

  def results
    @results ||= @circle.circle_statuses.joins(:status).eager_load(:status).to_a_paginated_by_id(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
  end

  def next_path
    api_v1_circle_statuses_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_circle_statuses_url pagination_params(min_id: pagination_since_id) unless results.empty?
  end

  def pagination_collection
    results
  end

  def records_continue?
    results.size == limit_param(DEFAULT_STATUSES_LIMIT)
  end
end
