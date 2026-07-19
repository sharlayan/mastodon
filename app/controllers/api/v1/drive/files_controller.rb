# frozen_string_literal: true

class Api::V1::Drive::FilesController < Api::V1::Drive::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:drive' }, only: [:index, :show, :find, :find_by_hash, :check_existence, :attached_notes]
  before_action -> { doorkeeper_authorize! :write, :'write:media', :'write:drive' }, except: [:index, :show, :find, :find_by_hash, :check_existence, :attached_notes]
  before_action :enforce_upload_rate_limit!, only: [:create, :upload_from_url]
  before_action :set_file, only: [:show, :update, :destroy, :attach, :transfer_to_posts, :attached_notes]
  after_action :insert_pagination_headers, only: :index

  LIMIT = 40
  BULK_LIMIT = 100

  def index
    @files = load_files
    render json: @files, each_serializer: REST::DriveFileSerializer, attached_ids: attached_ids_for(@files)
  end

  def show
    render json: @file, serializer: REST::DriveFileSerializer
  end

  def find
    @files = find_by_name
    render json: @files, each_serializer: REST::DriveFileSerializer, attached_ids: attached_ids_for(@files)
  end

  def find_by_hash
    @files = current_account.drive_files.where(md5: params[:md5]).to_a
    render json: @files, each_serializer: REST::DriveFileSerializer, attached_ids: attached_ids_for(@files)
  end

  def check_existence
    render json: { exists: current_account.drive_files.exists?(md5: params[:md5]) }
  end

  def attached_notes
    @statuses = load_attached_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer
  end

  def move_bulk
    ids = Array(bulk_file_ids).map(&:to_s).uniq.first(BULK_LIMIT)
    return render json: { error: 'file_ids is required', code: 'INVALID_PARAM' }, status: 422 if ids.empty?
    return render json: { error: 'No such folder', code: 'NO_SUCH_FOLDER' }, status: 404 unless valid_target_folder?

    @files = current_account.drive_files.where(id: ids).to_a
    DriveFile.where(id: @files.map(&:id)).update_all(folder_id: params[:folder_id].presence, updated_at: Time.now.utc) if @files.any?

    @files = current_account.drive_files.where(id: @files.map(&:id)).includes(:custom_name).to_a
    @files.each { |file| broadcast_drive_file(file, 'fileUpdated') }
    render json: @files, each_serializer: REST::DriveFileSerializer, attached_ids: attached_ids_for(@files)
  end

  def upload_from_url
    return render json: { error: 'url is required', code: 'INVALID_PARAM' }, status: 422 if params[:url].blank?
    return render json: { error: 'No such folder', code: 'NO_SUCH_FOLDER' }, status: 404 unless valid_target_folder?

    return render json: quota_error.merge(code: 'NO_FREE_SPACE'), status: 422 if drive_quota_full?

    accepted = DriveFileFromURLWorker.enqueue(current_account.id, params[:url].to_s, {
      'folder_id' => params[:folder_id].presence,
      'sensitive' => truthy_param?(:sensitive),
      'description' => params[:comment].presence || params[:description].presence,
    })

    render json: { accepted: accepted }, status: 202
  end

  def create
    return render json: { error: 'File is required', code: 'INVALID_PARAM' }, status: 422 if params[:file].blank?

    @file = CreateDriveFileService.new.call(
      account: current_account,
      user: current_user,
      file: params[:file],
      thumbnail: params[:thumbnail],
      name: params[:name],
      folder_id: params[:folder_id],
      folder_id_provided: params.key?(:folder_id),
      description: params[:description],
      sensitive: params[:sensitive]
    )

    render json: @file, serializer: REST::DriveFileSerializer
  rescue CreateDriveFileService::NoFreeSpaceError
    render json: quota_error.merge(code: 'NO_FREE_SPACE'), status: 422
  rescue CreateDriveFileService::NoSuchFolderError
    render json: { error: 'No such folder', code: 'NO_SUCH_FOLDER' }, status: 404
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    render json: { error: 'File type of uploaded media could not be verified', code: 'INVALID_FILE_TYPE' }, status: 422
  rescue Paperclip::Error => e
    Rails.logger.error "#{e.class}: #{e.message}"
    render json: { error: 'Error processing uploaded media' }, status: 500
  end

  def update
    attributes = drive_metadata_params
    name = attributes.delete(:name)

    @file.display_name = name unless name.nil?
    @file.update!(attributes)
    broadcast_drive_file(@file, 'fileUpdated')

    render json: @file, serializer: REST::DriveFileSerializer
  end

  def destroy
    deleted_id = @file.id

    if @file.destroy
      broadcast_drive_file(deleted_id, 'fileDeleted')
      render_empty
    else
      render json: in_usage_error, status: 422
    end
  end

  def attach
    attachment = @file.with_lock do
      @file.build_pointer(current_account).tap(&:save!)
    end
    render json: attachment, serializer: REST::MediaAttachmentSerializer
  end

  def transfer_to_posts
    count = TransferDriveFileToMediaAttachmentsService.new.call(@file)
    render json: { transferred: count }
  rescue TransferDriveFileToMediaAttachmentsService::NotAttachedError
    render json: { error: 'Drive file is not attached to a post', code: 'NOT_ATTACHED' }, status: 422
  rescue TransferDriveFileToMediaAttachmentsService::UnsupportedFileError
    render json: { error: 'Drive file cannot be converted to a media attachment', code: 'INVALID_FILE_TYPE' }, status: 422
  end

  private

  def enforce_upload_rate_limit!
    return if current_user.can_extra?(:bypass_rate_limit)

    RateLimiter.new(current_account, family: :drive_uploads).record!
  end

  def drive_quota_full?
    quota = current_account.drive_quota_bytes
    quota.positive? && current_account.drive_files.sum(:storage_file_size).to_i >= quota
  end

  def set_file
    @file = current_account.drive_files.find(params[:id])
  end

  def find_by_name
    scope = current_account.drive_files.eager_load(:custom_name)
    scope = params[:folder_id].present? ? scope.where(folder_id: params[:folder_id]) : scope.where(folder_id: nil)
    scope.where('COALESCE(drive_file_names.name, drive_files.file_file_name) = ?', params[:name]).to_a
  end

  def load_attached_statuses
    status_ids = @file.media_attachments.attached.where.not(status_id: nil).distinct.pluck(:status_id)
    return [] if status_ids.empty?

    scope = apply_date_range(Status.where(id: status_ids))
    statuses = scope.paginate_by_max_id(limit_param(LIMIT), params[:max_id], params[:since_id]).to_a
    statuses.select! { |status| StatusPolicy.new(current_account, status).show? }
    Status.preload_cacheable_associations(statuses)
    statuses
  end

  def bulk_file_ids
    params[:file_ids] || params[:fileIds]
  end

  def valid_target_folder?
    params[:folder_id].blank? || current_account.drive_folders.exists?(id: params[:folder_id])
  end

  def load_files
    scope = current_account.drive_files.includes(:custom_name)
    scope = params[:folder_id].present? ? scope.where(folder_id: params[:folder_id]) : scope.where(folder_id: nil) if params.key?(:folder_id) && !truthy_param?(:orphaned)
    scope = scope.where(type: params[:type]) if params[:type].present? && DriveFile.types.key?(params[:type])
    scope = scope.orphaned if truthy_param?(:orphaned)
    scope = apply_date_range(scope)
    scope = scope.paginate_by_max_id(limit_param(LIMIT), params[:max_id], params[:since_id])
    apply_sort(scope)
  end

  def apply_sort(scope)
    case params[:sort]
    when '+createdAt' then scope.reorder(id: :desc)
    when '-createdAt' then scope.reorder(id: :asc)
    when '+name' then scope.reorder(file_file_name: :desc, id: :desc)
    when '-name' then scope.reorder(file_file_name: :asc, id: :desc)
    when '+size' then scope.reorder(file_file_size: :desc, id: :desc)
    when '-size' then scope.reorder(file_file_size: :asc, id: :desc)
    else scope
    end
  end

  def attached_ids_for(files)
    ids = files.map(&:id)
    return Set.new if ids.empty?

    MediaAttachment.in_use.where(drive_file_id: ids).distinct.pluck(:drive_file_id).to_set
  end

  def next_path
    api_v1_drive_files_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_drive_files_url pagination_params(since_id: pagination_since_id) unless @files.empty?
  end

  def pagination_collection
    @files
  end

  def records_continue?
    @files.size == limit_param(LIMIT)
  end

  def pagination_params(core_params)
    params.slice(:limit, :folder_id, :type, :orphaned, :sort, :since_date, :until_date).permit(:limit, :folder_id, :type, :orphaned, :sort, :since_date, :until_date).merge(core_params)
  end

  def drive_metadata_params
    params.permit(:description, :folder_id, :sensitive, :name)
  end

  def quota_error
    { error: 'Drive storage quota exceeded' }
  end

  def in_usage_error
    { error: 'Drive file is currently in use', code: 'ATTACHED' }
  end
end
