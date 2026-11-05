# frozen_string_literal: true

class Api::V1::FederationUniversesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read }
  before_action :require_user!
  before_action :require_enabled!

  def show
    render json: Rails.cache.fetch(cache_key, expires_in: 1.hour) { Sharlayan::FederationUniverse.new.as_json }
  end

  private

  def cache_key
    edges = FederationInstanceEdge.pick(Arel.sql('MAX(updated_at)'), Arel.sql('COUNT(*)'))
    ['federation_universe', *edges]
  end

  def require_enabled!
    head 404 unless Sharlayan::FederationEdgeAggregator.enabled?
  end
end
