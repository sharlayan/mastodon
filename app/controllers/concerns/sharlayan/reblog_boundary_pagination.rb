# frozen_string_literal: true

module Sharlayan::ReblogBoundaryPagination
  extend ActiveSupport::Concern

  ACTIONABLE_BOUNDARY_CLIENTS = /\btusky\b/i

  included do
    before_action :rewrite_actionable_boundary!
  end

  private

  def rewrite_actionable_boundary!
    return if params[:max_id].blank? || params[:min_id].present?
    return unless actionable_boundary_client?
    return if current_account.nil?

    boundary = Sharlayan::HomeFeedBoundary.resolve(current_account, params[:max_id])
    params[:max_id] = boundary.to_s if boundary
  end

  def actionable_boundary_client?
    request.user_agent.to_s.match?(ACTIONABLE_BOUNDARY_CLIENTS)
  end
end
