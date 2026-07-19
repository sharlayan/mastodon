# frozen_string_literal: true

class Api::V1::Drive::FoldersController < Api::V1::Drive::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:drive' }, only: [:index, :show, :find]
  before_action -> { doorkeeper_authorize! :write, :'write:media', :'write:drive' }, except: [:index, :show, :find]
  before_action :set_folder, only: [:show, :update, :destroy]

  LIMIT = 40

  def index
    @folders = load_folders
    render json: @folders, each_serializer: REST::DriveFolderSerializer
  end

  def show
    render json: @folder, serializer: REST::DriveFolderSerializer, detail: true
  end

  def find
    @folders = find_by_name
    render json: @folders, each_serializer: REST::DriveFolderSerializer
  end

  def create
    @folder = current_account.drive_folders.create!(folder_params)
    broadcast_drive_folder(@folder, 'folderCreated')
    render json: @folder, serializer: REST::DriveFolderSerializer
  end

  def update
    @folder.update!(folder_params)
    broadcast_drive_folder(@folder, 'folderUpdated')
    render json: @folder, serializer: REST::DriveFolderSerializer
  end

  def destroy
    deleted_id = @folder.id
    @folder.destroy!
    broadcast_drive_folder(deleted_id, 'folderDeleted')
    render_empty
  end

  private

  def load_folders
    scope = current_account.drive_folders
    return scope.ordered unless paginated_query?

    scope = params[:parent_id].present? ? scope.where(parent_id: params[:parent_id]) : scope.where(parent_id: nil) if params.key?(:parent_id)
    scope = apply_date_range(scope)
    scope.paginate_by_max_id(limit_param(LIMIT), params[:max_id], params[:since_id])
  end

  def find_by_name
    scope = current_account.drive_folders.where(name: params[:name])
    scope = params[:parent_id].present? ? scope.where(parent_id: params[:parent_id]) : scope.where(parent_id: nil)
    scope.to_a
  end

  def paginated_query?
    params.key?(:parent_id) || params[:max_id].present? || params[:since_id].present? ||
      params[:since_date].present? || params[:until_date].present? || params[:limit].present?
  end

  def set_folder
    @folder = current_account.drive_folders.find(params[:id])
  end

  def folder_params
    params.permit(:name, :parent_id)
  end
end
