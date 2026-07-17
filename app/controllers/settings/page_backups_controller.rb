# frozen_string_literal: true

class Settings::PageBackupsController < Settings::BaseController
  before_action :require_pages_enabled!

  def show; end

  def create
    send_data Sharlayan::PageBackupService.new(current_account).export,
              filename: 'pages-backup.zip', type: 'application/zip', disposition: 'attachment'
  end

  def update
    Sharlayan::PageBackupService.new(current_account).import!(params.expect(page_backup: [:data, :mode]).fetch(:data), overwrite: params.dig(:page_backup, :mode) == 'overwrite')
    redirect_to settings_page_backup_path, notice: t('page_backups.imported')
  rescue Sharlayan::PageBackupService::InvalidArchive
    redirect_to settings_page_backup_path, alert: t('page_backups.invalid_archive')
  end

  private

  def require_pages_enabled!
    not_found unless Setting.pages_enabled
  end
end
