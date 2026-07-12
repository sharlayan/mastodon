# frozen_string_literal: true

class Api::V1::Statuses::ClipsController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }
  before_action :require_user!
  before_action :set_status

  def index
    @clips = current_account.clips.where(id: ClipStatus.where(status_id: @status.id).select(:clip_id)).to_a
    render json: @clips, each_serializer: REST::ClipSerializer, relationships: ClipRelationshipsPresenter.new(@clips, current_account.id)
  end

  private

  def require_feature_enabled!
    not_found unless Setting.clips_enabled
  end

  def set_status
    @status = Status.find(params[:status_id])
    not_found unless StatusPolicy.new(current_account, @status).show?
  rescue Mastodon::NotPermittedError
    not_found
  end
end
