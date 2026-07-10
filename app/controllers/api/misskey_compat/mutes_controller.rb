# frozen_string_literal: true

class Api::MisskeyCompat::MutesController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :set_target!, except: [:index, :renote_list]

  def index
    mutes = current_account.mute_relationships.includes(:target_account).order(id: :desc)
    mutes = mutes.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    mutes = mutes.where('mutes.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    mutes = mutes.limit(pagination_limit(default: 30, max: 100))

    render json: mutes.map { |mute| serialize_muting(mute) }
  end

  def create
    MuteService.new.call(current_account, @target, notifications: ActiveModel::Type::Boolean.new.cast(params.fetch(:notifications, true)))
    head 204
  end

  def destroy
    UnmuteService.new.call(current_account, @target)
    head 204
  end

  def renote_list
    follows = current_account.active_relationships.includes(:target_account).where(show_reblogs: false).order(id: :desc)
    follows = follows.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    follows = follows.where('follows.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    follows = follows.limit(pagination_limit(default: 30, max: 100))

    render json: follows.map { |follow| serialize_renote_muting(follow) }
  end

  def renote_create
    follow = current_account.active_relationships.find_by(target_account: @target)
    follow&.update!(show_reblogs: false)
    head 204
  end

  def renote_destroy
    follow = current_account.active_relationships.find_by(target_account: @target)
    follow&.update!(show_reblogs: true)
    head 204
  end

  private

  def serialize_muting(mute)
    {
      id: mute.id.to_s,
      createdAt: mute.created_at.iso8601,
      expiresAt: nil,
      muteeId: mute.target_account_id.to_s,
      mutee: MisskeyCompat::UserSerializer.serialize(mute.target_account, detailed: true, viewer: current_account),
    }
  end

  def serialize_renote_muting(follow)
    {
      id: follow.id.to_s,
      createdAt: follow.created_at.iso8601,
      muteeId: follow.target_account_id.to_s,
      mutee: MisskeyCompat::UserSerializer.serialize(follow.target_account, detailed: true, viewer: current_account),
    }
  end

  def set_target!
    @target = Account.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
