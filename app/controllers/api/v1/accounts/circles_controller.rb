# frozen_string_literal: true

class Api::V1::Accounts::CirclesController < Api::V1::Accounts::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }
  before_action :require_user!
  before_action :set_account

  def index
    @circles = @account.suspended? ? [] : current_account.circles.joins(:circle_accounts).where(circle_accounts: { account_id: @account.id })
    render json: @circles, each_serializer: REST::CircleSerializer
  end

  private

  def require_feature_enabled!
    not_found unless Setting.circles_enabled
  end
end
