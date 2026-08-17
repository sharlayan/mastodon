# frozen_string_literal: true

class Api::V1::Timelines::AdminController < Api::V1::Timelines::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }
  before_action :require_user!
  before_action :require_admin_timeline_enabled!
  before_action :require_admin_timeline_access!

  PERMITTED_PARAMS = %i(limit hide_public hide_unlisted hide_private group_direct).freeze

  def show
    with_read_replica do
      @statuses = load_statuses
      @relationships = StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
    end

    render json: @statuses,
           each_serializer: REST::StatusSerializer,
           relationships: @relationships,
           rp_admin: soft_hide_viewer?
  end

  private

  def load_statuses
    preload_collection(admin_statuses, Status).tap do |statuses|
      ActiveRecord::Associations::Preloader.new(records: statuses, associations: :rp_hidden_status).call if soft_hide_viewer?
    end
  end

  def admin_statuses
    base = soft_hide_viewer? ? Status.with_rp_hidden : Status
    scope = base.admin_timeline_eligible.where(account: Account.local).order(id: :desc)

    scope = scope.where.not(visibility: hidden_visibilities) if hidden_visibilities.any?

    scope = exclude_owner_conversations(scope) unless owner_viewer?
    scope = scope.where(account_id: current_account.followers.select(:id)) unless full_viewer?

    scope = scope.where('statuses.visibility != ? OR statuses.in_reply_to_id IS NULL', Status.visibilities[:direct]) if truthy_param?(:group_direct)

    scope = scope.where(id: ...params[:max_id].to_i) if params[:max_id].present?
    scope = scope.where(id: params[:min_id].to_i..) if params[:min_id].present?
    scope = scope.where(id: params[:since_id].to_i..) if params[:since_id].present? && params[:min_id].blank?

    scope.limit(limit_param(DEFAULT_STATUSES_LIMIT))
  end

  def exclude_owner_conversations(scope)
    account_ids = owner_account_ids
    return scope if account_ids.empty?

    scope.where(<<~SQL.squish, direct: Status.visibilities[:direct], owners: account_ids)
      statuses.visibility != :direct
      OR (statuses.account_id NOT IN (:owners)
          AND NOT EXISTS (
            SELECT 1 FROM mentions m
            WHERE m.status_id = statuses.id AND m.account_id IN (:owners)
          ))
    SQL
  end

  def owner_account_ids
    @owner_account_ids ||= Sharlayan::AdminTimeline.owner_account_ids
  end

  def owner_viewer?
    Sharlayan::AdminTimeline.owner_role?(current_user.role)
  end

  def full_viewer?
    Sharlayan::AdminTimeline.full_viewer_role?(current_user.role)
  end

  def soft_hide_viewer?
    Setting.soft_hide_deletion && owner_viewer?
  end

  def hidden_visibilities
    @hidden_visibilities ||= [].tap do |visibilities|
      visibilities << :public if truthy_param?(:hide_public)
      visibilities << :unlisted if truthy_param?(:hide_unlisted)
      visibilities << :private if truthy_param?(:hide_private)
    end
  end

  def require_admin_timeline_enabled!
    not_found unless Sharlayan::AdminTimeline.enabled?
  end

  def require_admin_timeline_access!
    render json: { error: 'This action is not allowed' }, status: 403 unless Sharlayan::AdminTimeline.role_can_view?(current_user.role)
  end

  def next_path
    api_v1_timelines_admin_url next_path_params
  end

  def prev_path
    api_v1_timelines_admin_url prev_path_params
  end
end
