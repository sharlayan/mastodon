# frozen_string_literal: true

class Api::V1::Timelines::AdminController < Api::V1::Timelines::BaseController
  include RoleplayModeHelper

  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }
  before_action :require_user!
  before_action :require_roleplay_mode!
  before_action :require_admin_timeline_access!

  PERMITTED_PARAMS = %i(limit hide_public hide_unlisted hide_private group_direct).freeze

  def show
    with_read_replica do
      @statuses = load_statuses
      @relationships = StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
    end

    render json: @statuses,
           each_serializer: REST::StatusSerializer,
           relationships: @relationships
  end

  private

  def load_statuses
    preload_collection(admin_statuses, Status)
  end

  def admin_statuses
    scope = Status.where(account: Account.local).order(id: :desc)

    scope = scope.where.not(visibility: hidden_visibilities) if hidden_visibilities.any?

    scope = exclude_owner_conversations(scope) unless owner_viewer?

    # Direct conversation grouping: hide threaded direct replies, keeping only
    # the post that starts each direct conversation (and every other visibility).
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
    Account.joins(:user).where(users: { role_id: owner_role_ids }).pluck(:id)
  end

  def owner_role_ids
    @owner_role_ids ||= UserRole.assignable.where(position: top_role_position).pluck(:id)
  end

  def owner_viewer?
    role = current_user.role
    !role.everyone? && role.position == top_role_position
  end

  def top_role_position
    @top_role_position ||= UserRole.assignable.maximum(:position)
  end

  def hidden_visibilities
    @hidden_visibilities ||= [].tap do |visibilities|
      visibilities << :public if truthy_param?(:hide_public)
      visibilities << :unlisted if truthy_param?(:hide_unlisted)
      visibilities << :private if truthy_param?(:hide_private)
    end
  end

  def require_roleplay_mode!
    not_found unless roleplay_mode?
  end

  def require_admin_timeline_access!
    render json: { error: 'This action is not allowed' }, status: 403 unless current_user.role.can_extra?(:view_admin_timeline)
  end

  def next_path
    api_v1_timelines_admin_url next_path_params
  end

  def prev_path
    api_v1_timelines_admin_url prev_path_params
  end
end
