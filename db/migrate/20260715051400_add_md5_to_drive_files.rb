# frozen_string_literal: true

class AddMd5ToDriveFiles < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    safety_assured { add_column :drive_files, :md5, :string } unless column_exists?(:drive_files, :md5)
    add_index :drive_files, [:account_id, :md5], name: :index_drive_files_on_account_id_and_md5, algorithm: :concurrently unless index_exists?(:drive_files, [:account_id, :md5], name: :index_drive_files_on_account_id_and_md5)

    backfill_md5
  end

  def down
    remove_index :drive_files, name: :index_drive_files_on_account_id_and_md5, algorithm: :concurrently if index_exists?(:drive_files, [:account_id, :md5], name: :index_drive_files_on_account_id_and_md5)
    remove_column :drive_files, :md5 if column_exists?(:drive_files, :md5)
  end

  private

  def backfill_md5
    DriveFile.reset_column_information

    DriveFile.where(md5: nil).find_each do |drive_file|
      digest = compute_md5(drive_file)
      drive_file.update_column(:md5, digest) if digest.present?
    rescue => e
      Rails.logger.warn("Skipping md5 backfill for DriveFile##{drive_file.id}: #{e.message}")
    end
  end

  def compute_md5(drive_file)
    return if drive_file.file_file_name.blank?

    path = Paperclip.io_adapters.for(drive_file.file).path
    return if path.blank?

    Digest::MD5.file(path).hexdigest
  end
end
