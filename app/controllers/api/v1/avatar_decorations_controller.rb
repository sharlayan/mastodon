# frozen_string_literal: true

class Api::V1::AvatarDecorationsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write, :'write:mutes' }, only: [:create_mute, :destroy_mute]
  before_action :require_user!, only: [:create_mute, :destroy_mute]
  before_action :require_feature_enabled!

  def index
    @decorations = AvatarDecoration.local.approved.order(:name)
    render json: @decorations, each_serializer: REST::AvatarDecorationSerializer
  end

  def create_mute
    if params[:account_id].present?
      target = Account.find(params[:account_id])
      mute = current_account.avatar_decoration_mutes.find_or_create_by!(target_account: target)
    elsif params[:domain].present?
      domain = TagManager.instance.normalize_domain(params[:domain])
      return render json: { error: 'Invalid domain' }, status: 422 if domain.blank?

      mute = current_account.avatar_decoration_mutes.find_or_create_by!(target_domain: domain)
    else
      return render json: { error: 'Must provide account_id or domain' }, status: 422
    end

    render json: mute, serializer: REST::AvatarDecorationMuteSerializer
  end

  def destroy_mute
    mute = current_account.avatar_decoration_mutes.find(params[:id])
    mute.destroy!
    render_empty
  end

  private

  def require_feature_enabled!
    not_found unless Setting.avatar_decorations_enabled
  end
end
