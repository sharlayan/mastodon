# frozen_string_literal: true

class Api::V1::Accounts::ClipsController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { authorize_if_got_token! :read, :'read:lists' }
  before_action :set_account

  def index
    cache_if_unauthenticated!
    @clips = load_clips
    render json: @clips, each_serializer: REST::ClipSerializer, relationships: ClipRelationshipsPresenter.new(@clips, current_account&.id)
  end

  private

  def require_feature_enabled!
    not_found unless Setting.clips_enabled
  end

  def set_account
    @account = Account.find(params[:account_id])
  end

  def load_clips
    return [] if @account.unavailable?

    scope = @account.clips.order(id: :desc)
    scope = scope.public_clips unless owner?
    scope.to_a
  end

  def owner?
    current_account.present? && current_account.id == @account.id
  end
end
