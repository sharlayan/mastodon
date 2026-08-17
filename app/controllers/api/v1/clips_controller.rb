# frozen_string_literal: true

class Api::V1::ClipsController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:index, :show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:index, :show]

  before_action :require_user!, except: [:show]
  before_action :set_clip, only: [:show, :update, :destroy]

  def index
    @clips = Clip.where(account: current_account).to_a
    render json: @clips, each_serializer: REST::ClipSerializer, relationships: ClipRelationshipsPresenter.new(@clips, current_account.id)
  end

  def show
    render json: @clip, serializer: REST::ClipSerializer
  end

  def create
    @clip = current_account.with_lock { current_account.clips.create!(clip_params) }
    render json: @clip, serializer: REST::ClipSerializer
  end

  def update
    authorize_owner!
    @clip.update!(clip_params)
    render json: @clip, serializer: REST::ClipSerializer
  end

  def destroy
    authorize_owner!
    @clip.destroy!
    render_empty
  end

  private

  def require_feature_enabled!
    not_found unless Setting.clips_enabled
  end

  def set_clip
    @clip = Clip.find(params[:id])
    not_found unless @clip.visible_to?(current_account)
  end

  def authorize_owner!
    not_found unless @clip.account_id == current_account.id
  end

  def clip_params
    params.permit(:title, :description, :public)
  end
end
