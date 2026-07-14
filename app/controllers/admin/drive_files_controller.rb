# frozen_string_literal: true

module Admin
  class DriveFilesController < BaseController
    before_action :set_drive_file, only: [:destroy]

    def index
      authorize :drive_file, :index?

      @drive_files = filtered_drive_files.page(params[:page])
    end

    def destroy
      authorize :drive_file, :destroy?

      if @drive_file.destroy
        log_action :destroy, @drive_file
        flash[:notice] = I18n.t('generic.changes_saved_msg')
      else
        flash[:alert] = I18n.t('admin.drive_files.attached_error')
      end

      redirect_to admin_drive_files_path(filter_params)
    end

    def destroy_orphaned
      authorize :drive_file, :destroy?

      DriveFile.orphaned.find_each(&:destroy)

      flash[:notice] = I18n.t('generic.changes_saved_msg')
      redirect_to admin_drive_files_path
    end

    private

    def set_drive_file
      @drive_file = DriveFile.find(params[:id])
    end

    def filtered_drive_files
      scope = DriveFile.includes(:account).ordered
      scope = scope.orphaned if params[:orphaned] == '1'
      scope
    end

    def filter_params
      params.slice(:orphaned, :page).permit(:orphaned, :page)
    end
    helper_method :filter_params
  end
end
