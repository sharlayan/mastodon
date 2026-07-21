# frozen_string_literal: true

class Api::MisskeyCompat::DriveFoldersController < Api::MisskeyCompat::BaseController
  requires_write_scope :create, :update, :destroy
  requires_misskey_permission 'read:drive', :index, :show, :find
  requires_misskey_permission 'write:drive', :create, :update, :destroy

  before_action :require_user!
  before_action :require_drive_enabled!

  LIMIT = 100

  def index
    folders = folder_scope(:folderId).order(id: :desc).limit(pagination_limit(default: 10, max: LIMIT))
    render json: folders.map { |folder| MisskeyCompat::DriveFolderSerializer.serialize(folder) }
  end

  def show
    render json: MisskeyCompat::DriveFolderSerializer.serialize(find_folder!, detail: true)
  end

  def create
    folder = current_account.drive_folders.create!(name: params[:name], parent_id: validated_parent_id)
    render json: MisskeyCompat::DriveFolderSerializer.serialize(folder)
  end

  def update
    folder = find_folder!
    attributes = {}
    attributes[:name] = params[:name] if params.key?(:name)
    attributes[:parent_id] = validated_parent_id if params.key?(:parentId)
    folder.update!(attributes)
    render json: MisskeyCompat::DriveFolderSerializer.serialize(folder)
  end

  def destroy
    find_folder!.destroy!
    head 204
  end

  def find
    return render_invalid_param('#/properties/name', 'name required') if params[:name].blank?

    folders = folder_scope(:parentId).where(name: params[:name].to_s)
    render json: folders.map { |folder| MisskeyCompat::DriveFolderSerializer.serialize(folder) }
  end

  private

  def require_drive_enabled!
    render_error('Drive is not available on this server', 'UNAVAILABLE', 400) unless Setting.drive_enabled
  end

  def folder_scope(parent_key)
    scope = current_account.drive_folders.includes(:parent)
    scope = params[parent_key].present? ? scope.where(parent_id: params[parent_key]) : scope.where(parent_id: nil)
    scope = apply_compat_date_range(scope)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('drive_folders.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope
  end

  def find_folder!
    current_account.drive_folders.find(params[:folderId])
  rescue ActiveRecord::RecordNotFound
    raise CreateDriveFileService::NoSuchFolderError
  end

  def validated_parent_id
    parent_id = params[:parentId].presence
    return if parent_id.nil?
    return parent_id if current_account.drive_folders.exists?(id: parent_id)

    raise CreateDriveFileService::NoSuchFolderError
  end

  rescue_from CreateDriveFileService::NoSuchFolderError do
    render_error('No such folder', 'NO_SUCH_FOLDER', 404)
  end
end
