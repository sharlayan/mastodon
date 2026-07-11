# frozen_string_literal: true

class Admin::BoardAnnouncementsController < Admin::BaseController
  before_action :set_announcements, only: :index
  before_action :set_announcement, except: [:index, :new, :create, :upload_attachment, :destroy_attachment]

  def index
    authorize :board_announcement, :index?
  end

  def new
    authorize :board_announcement, :create?

    @announcement = BoardAnnouncement.new
  end

  def edit
    authorize :board_announcement, :update?
  end

  def create
    authorize :board_announcement, :create?

    @announcement = BoardAnnouncement.new(resource_params)
    @announcement.account = current_account

    if @announcement.save
      log_action :create, @announcement
      redirect_to admin_board_announcements_path, notice: I18n.t('admin.board_announcements.created_msg')
    else
      render :new
    end
  end

  def update
    authorize :board_announcement, :update?

    if @announcement.update(resource_params)
      log_action :update, @announcement
      redirect_to admin_board_announcements_path, notice: I18n.t('admin.board_announcements.updated_msg')
    else
      render :edit
    end
  end

  def upload_attachment
    authorize :board_announcement, :create?

    attachment = BoardAnnouncementAttachment.new(file: params[:file])

    if attachment.save
      render json: attachment, serializer: REST::BoardAnnouncementAttachmentSerializer
    else
      render json: { error: attachment.errors.full_messages.join(', ') }, status: 422
    end
  end

  def destroy_attachment
    authorize :board_announcement, :update?

    attachment = BoardAnnouncementAttachment.find(params[:attachment_id])
    attachment.destroy!

    head 204
  end

  def publish
    authorize :board_announcement, :update?

    @announcement.publish!
    log_action :update, @announcement
    redirect_to admin_board_announcements_path, notice: I18n.t('admin.board_announcements.published_msg')
  end

  def unpublish
    authorize :board_announcement, :update?

    @announcement.unpublish!
    log_action :update, @announcement
    redirect_to admin_board_announcements_path, notice: I18n.t('admin.board_announcements.unpublished_msg')
  end

  def destroy
    authorize :board_announcement, :destroy?

    @announcement.destroy!
    log_action :destroy, @announcement
    redirect_to admin_board_announcements_path, notice: I18n.t('admin.board_announcements.destroyed_msg')
  end

  private

  def set_announcements
    @announcements = BoardAnnouncement.reverse_chronological.left_joins(:reads).group(:id).select('board_announcements.*, COUNT(board_announcement_reads.id) AS reads_count').page(params[:page])
  end

  def set_announcement
    @announcement = BoardAnnouncement.find(params[:id])
  end

  def resource_params
    params
      .expect(board_announcement: [:title, :text, :published, :sort_priority, :icon, :display, :need_confirmation_to_read, :silence, :for_existing_users, { attachment_ids: [] }])
  end
end
