# frozen_string_literal: true

class Api::V1::FederationUniversesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!
  before_action :require_enabled!

  def show
    render json: Sharlayan::FederationUniverse.new.as_json
  end

  private

  def require_enabled!
    head 404 unless Sharlayan::FederationEdgeAggregator.enabled?
  end
end
