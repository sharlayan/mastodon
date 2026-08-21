# frozen_string_literal: true

class Api::V1::Timelines::RpHiddenController < Api::V1::Timelines::BaseController
  include Authorization

  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }
  before_action :require_user!
  before_action :require_owner!

  PERMITTED_PARAMS = %i(limit).freeze

  def show
    with_read_replica do
      @statuses = load_statuses
      @statuses.each { |status| authorize status, :show? }
      @relationships = StatusRelationshipsPresenter.new(@statuses, current_account.id)
    end

    render json: @statuses,
           each_serializer: REST::StatusSerializer,
           relationships: @relationships,
           rp_admin: true
  end

  private

  def load_statuses
    preload_collection(hidden_statuses, Status).tap do |statuses|
      ActiveRecord::Associations::Preloader.new(records: statuses, associations: :rp_hidden_status).call
    end
  end

  def hidden_statuses
    Status.with_rp_hidden
      .joins(:rp_hidden_status)
      .order(id: :desc)
      .paginate_by_max_id(limit_param(DEFAULT_STATUSES_LIMIT), params[:max_id], params[:since_id])
  end

  def require_owner!
    not_found unless Sharlayan::SoftHide.enabled? && owner?
  end

  def owner?
    role = current_user.role
    !role.everyone? && role.position == UserRole.assignable.maximum(:position)
  end

  def next_path
    api_v1_timelines_rp_hidden_url next_path_params
  end

  def prev_path
    api_v1_timelines_rp_hidden_url prev_path_params
  end
end
