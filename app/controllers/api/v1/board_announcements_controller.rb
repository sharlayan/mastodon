# frozen_string_literal: true

class Api::V1::BoardAnnouncementsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: :read
  before_action :require_user!
  before_action :check_enabled
  before_action :set_announcements, only: :index
  before_action :set_announcement, only: [:show, :read]

  def index
    render json: @announcements, each_serializer: REST::BoardAnnouncementSerializer
  end

  def show
    render json: @announcement, serializer: REST::BoardAnnouncementSerializer
  end

  def unread_count
    count = BoardAnnouncement.published
      .for_account(current_account)
      .where(silence: false)
      .where.not(id: BoardAnnouncementRead.where(account_id: current_account.id).select(:board_announcement_id))
      .count
    render json: { count: count }
  end

  def read
    BoardAnnouncementRead.find_or_create_by!(account: current_account, board_announcement: @announcement)
    render_empty
  end

  private

  def check_enabled
    not_found unless Setting.board_announcements_enabled
  end

  def set_announcements
    @announcements = BoardAnnouncement.published.for_account(current_account).reverse_chronological.includes(:attachments).page(params[:page])
    preload_read_state
  end

  def set_announcement
    @announcement = BoardAnnouncement.published.for_account(current_account).find(params[:id])
  end

  def preload_read_state
    read_ids = BoardAnnouncementRead.where(account_id: current_account.id, board_announcement_id: @announcements.map(&:id)).pluck(:board_announcement_id).to_set
    @announcements.each do |announcement|
      announcement.define_singleton_method(:read_by_current_user) { read_ids.include?(id) }
    end
  end
end
