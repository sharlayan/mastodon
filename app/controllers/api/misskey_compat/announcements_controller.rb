# frozen_string_literal: true

class Api::MisskeyCompat::AnnouncementsController < Api::MisskeyCompat::BaseController
  def index
    scope = BoardAnnouncement.published.reverse_chronological
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('board_announcements.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope = scope.includes(:attachments).limit(pagination_limit(default: 10, max: 100))

    render json: scope.map { |announcement| MisskeyCompat::AnnouncementSerializer.serialize(announcement, current_account: current_account) }
  end
end
