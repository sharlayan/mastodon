# frozen_string_literal: true

class Api::MisskeyCompat::DriveController < Api::MisskeyCompat::BaseController
  requires_write_scope :create, :update, :destroy, :move_bulk, :upload_from_url
  requires_misskey_permission 'read:drive', :attached_notes, :index, :show, :find, :find_by_hash, :check_existence
  requires_misskey_permission 'write:drive', :create, :update, :destroy, :move_bulk, :upload_from_url

  before_action :require_user!, except: :unavailable
  before_action :require_drive_enabled!, only: [:index, :show, :update, :destroy, :find, :find_by_hash, :check_existence, :move_bulk, :upload_from_url]
  before_action :enforce_upload_rate_limit!, only: [:create, :upload_from_url]
  before_action :enforce_search_rate_limit!, only: [:find, :find_by_hash]

  LIMIT = 100
  SEARCH_LIMIT = 20
  BULK_LIMIT = 100

  rescue_from MisskeyCompat::DriveFileResolver::NoSuchFileError do
    render_error('No such file', 'NO_SUCH_FILE', 404)
  end

  rescue_from MisskeyCompat::DriveFileResolver::AmbiguousFileError do
    render_invalid_param('#/properties/fileId', 'ambiguous file id')
  end

  rescue_from CreateDriveFileService::NoSuchFolderError do
    render_error('No such folder', 'NO_SUCH_FOLDER', 404)
  end

  def unavailable
    render_error('Drive is not available on this server', 'UNAVAILABLE', 400)
  end

  def attached_notes
    statuses = attached_statuses
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)

    render json: statuses.map { |note| MisskeyCompat::NoteSerializer.serialize(note, context: context) }
  end

  def index
    files = apply_file_sort(apply_file_range(file_scope)).limit(pagination_limit(default: 10, max: LIMIT)).to_a
    render json: files.map { |file| MisskeyCompat::DriveFileSerializer.serialize(file) }
  end

  def show
    render json: MisskeyCompat::DriveFileSerializer.serialize(find_file!)
  end

  def create
    return render_invalid_param('#/properties/file', 'file required') if params[:file].blank?

    return create_persistent_drive_file if Setting.drive_enabled

    media = current_account.media_attachments.create!(
      file: params[:file],
      thumbnail: params[:thumbnail],
      description: params[:comment].presence
    )

    render json: MisskeyCompat::DriveFileSerializer.serialize(media)
  rescue ActiveRecord::RecordInvalid, Mastodon::ValidationError => e
    render_error(e.to_s, 'INVALID_FILE', 400)
  end

  def update
    file = find_file!
    attributes = {}
    attributes[:folder_id] = validated_folder_id if params.key?(:folderId)
    attributes[:description] = params[:comment] if params.key?(:comment)
    attributes[:sensitive] = ActiveModel::Type::Boolean.new.cast(params[:isSensitive]) if params.key?(:isSensitive)
    file.display_name = params[:name] if params.key?(:name)
    file.update!(attributes)
    render json: MisskeyCompat::DriveFileSerializer.serialize(file)
  end

  def destroy
    file = find_file!
    return render_error('File is attached', 'ATTACHED', 422) unless file.destroy

    head 204
  end

  def find
    return render_invalid_param('#/properties/name', 'name required') if params[:name].blank?

    files = paginated_search(file_scope.eager_load(:custom_name).where('COALESCE(drive_file_names.name, drive_files.file_file_name) = ?', params[:name].to_s))
    render json: files.map { |file| MisskeyCompat::DriveFileSerializer.serialize(file) }
  end

  def find_by_hash
    return render_invalid_param('#/properties/md5', 'md5 required') if params[:md5].blank?

    render json: paginated_search(current_account.drive_files.where(md5: params[:md5].to_s)).map { |file| MisskeyCompat::DriveFileSerializer.serialize(file) }
  end

  def check_existence
    return render_invalid_param('#/properties/md5', 'md5 required') if params[:md5].blank?

    render json: current_account.drive_files.exists?(md5: params[:md5].to_s)
  end

  def move_bulk
    ids = Array(params[:fileIds]).map(&:to_s).uniq.first(BULK_LIMIT)
    return render_invalid_param('#/properties/fileIds', 'fileIds required') if ids.empty?

    folder_id = validated_folder_id
    files = current_account.drive_files.where(id: ids).to_a
    return render_error('No such file', 'NO_SUCH_FILE', 404) unless files.size == ids.size

    DriveFile.where(id: files.map(&:id)).update_all(folder_id: folder_id, updated_at: Time.current)
    head 204
  end

  def upload_from_url
    return render_invalid_param('#/properties/url', 'url required') if params[:url].blank?
    return render_error('Drive storage quota exceeded', 'NO_FREE_SPACE', 422) if drive_quota_full?

    DriveFileFromURLWorker.enqueue(current_account.id, params[:url].to_s, {
      'folder_id' => upload_folder_id,
      'sensitive' => ActiveModel::Type::Boolean.new.cast(params[:isSensitive]),
      'description' => params[:comment],
    })
    head 204
  end

  private

  def enforce_upload_rate_limit!
    return if Setting.rate_limit_bypass_enabled && current_user.can_extra?(:bypass_rate_limit)

    rate_limited?(:drive_uploads)
  end

  def enforce_search_rate_limit!
    rate_limited?(:drive_searches)
  end

  def paginated_search(scope)
    apply_file_range(scope).reorder(id: :desc).limit(pagination_limit(default: SEARCH_LIMIT, max: SEARCH_LIMIT)).to_a
  end

  def drive_quota_full?
    quota = current_account.drive_quota_bytes
    quota.positive? && current_account.drive_files.sum(:storage_file_size).to_i >= quota
  end

  def require_drive_enabled!
    render_error('Drive is not available on this server', 'UNAVAILABLE', 400) unless Setting.drive_enabled
  end

  def find_file!
    current_account.drive_files.find(params[:fileId])
  rescue ActiveRecord::RecordNotFound
    raise MisskeyCompat::DriveFileResolver::NoSuchFileError
  end

  def file_scope
    scope = current_account.drive_files.includes(:custom_name)
    scope = params[:folderId].present? ? scope.where(folder_id: params[:folderId]) : scope.where(folder_id: nil)
    scope = scope.where(file_content_type: params[:type]) if params[:type].present?
    apply_compat_date_range(scope)
  end

  def apply_file_range(scope)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('drive_files.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope
  end

  def apply_file_sort(scope)
    case params[:sort]
    when '-createdAt' then scope.reorder(id: :asc)
    when '+name' then scope.reorder(file_file_name: :desc, id: :desc)
    when '-name' then scope.reorder(file_file_name: :asc, id: :desc)
    when '+size' then scope.reorder(file_file_size: :desc, id: :desc)
    when '-size' then scope.reorder(file_file_size: :asc, id: :desc)
    else scope.reorder(id: :desc)
    end
  end

  def validated_folder_id
    folder_id = params[:folderId].presence
    return if folder_id.nil?
    return folder_id if current_account.drive_folders.exists?(id: folder_id)

    raise CreateDriveFileService::NoSuchFolderError
  end

  def upload_folder_id
    return validated_folder_id if params.key?(:folderId)

    folder_id = current_user.settings[:drive_default_folder_id].presence
    folder_id if folder_id && current_account.drive_folders.exists?(id: folder_id)
  end

  def attached_statuses
    drive_file = Setting.drive_enabled ? current_account.drive_files.find_by(id: params[:fileId]) : nil
    media = current_account.media_attachments.find_by(id: params[:fileId], drive_file_id: nil)
    raise MisskeyCompat::DriveFileResolver::AmbiguousFileError if drive_file && media

    status_ids = if drive_file
                   drive_file.media_attachments.attached.where.not(status_id: nil).distinct.pluck(:status_id)
                 elsif media&.status_id
                   [media.status_id]
                 else
                   []
                 end
    raise MisskeyCompat::DriveFileResolver::NoSuchFileError if drive_file.nil? && media.nil?

    scope = apply_compat_date_range(Status.where(id: status_ids))
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('statuses.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.order(id: :desc).limit(pagination_limit(default: 10, max: LIMIT)).to_a.select { |status| StatusPolicy.new(current_account, status).show? }
  end

  def create_persistent_drive_file
    drive_file = CreateDriveFileService.new.call(
      account: current_account,
      user: current_user,
      file: params[:file],
      thumbnail: params[:thumbnail],
      name: params[:name],
      folder_id: params[:folderId],
      folder_id_provided: params.key?(:folderId),
      description: params[:comment],
      sensitive: ActiveModel::Type::Boolean.new.cast(params[:isSensitive])
    )

    render json: MisskeyCompat::DriveFileSerializer.serialize(drive_file)
  rescue CreateDriveFileService::NoFreeSpaceError
    render_error('Drive storage quota exceeded', 'NO_FREE_SPACE', 422)
  rescue CreateDriveFileService::NoSuchFolderError
    render_error('No such folder', 'NO_SUCH_FOLDER', 404)
  rescue ActiveRecord::RecordInvalid
    render_error('File type of uploaded media is not allowed', 'INVALID_FILE_TYPE', 422)
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    render_error('File type of uploaded media could not be verified', 'INVALID_FILE_TYPE', 422)
  rescue Paperclip::Error => e
    Rails.logger.error "#{e.class}: #{e.message}"
    render_error('Error processing uploaded media', 'INTERNAL_ERROR', 500, kind: 'server')
  end
end
