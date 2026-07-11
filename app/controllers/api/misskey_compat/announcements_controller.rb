# frozen_string_literal: true

class Api::MisskeyCompat::AnnouncementsController < Api::MisskeyCompat::BaseController
  def index
    scope = BoardAnnouncement.published.reverse_chronological
    scope = scope.for_account(current_account) if current_account
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('board_announcements.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    announcements = scope.includes(:attachments).limit(pagination_limit(default: 10, max: 100)).to_a
    preload_read_state(announcements)

    render json: announcements.map { |announcement| MisskeyCompat::AnnouncementSerializer.serialize(announcement, current_account: current_account) }
  end

  private

  def preload_read_state(announcements)
    return if current_account.nil? || announcements.empty?

    read_ids = BoardAnnouncementRead.where(account_id: current_account.id, board_announcement_id: announcements.map(&:id)).pluck(:board_announcement_id).to_set
    announcements.each do |announcement|
      announcement.define_singleton_method(:read_by_current_user) { read_ids.include?(id) }
    end
  end
end
