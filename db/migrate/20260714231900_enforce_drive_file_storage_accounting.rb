# frozen_string_literal: true

class EnforceDriveFileStorageAccounting < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    safety_assured { add_column :drive_files, :storage_file_size, :bigint, default: 0, null: false } unless column_exists?(:drive_files, :storage_file_size)

    safety_assured do
      execute <<~SQL.squish
        UPDATE drive_files
        SET storage_file_size = COALESCE(file_file_size, 0) + COALESCE(thumbnail_file_size, 0)
        WHERE storage_file_size = 0
      SQL
    end

    add_index :drive_files, [:account_id, :sha256], unique: true, name: :index_drive_files_on_account_and_sha256_unique, algorithm: :concurrently unless index_exists?(:drive_files, [:account_id, :sha256], name: :index_drive_files_on_account_and_sha256_unique, unique: true)
    remove_index :drive_files, name: :index_drive_files_on_account_id_and_sha256, algorithm: :concurrently if index_exists?(:drive_files, [:account_id, :sha256], name: :index_drive_files_on_account_id_and_sha256)
  end

  def down
    add_index :drive_files, [:account_id, :sha256], name: :index_drive_files_on_account_id_and_sha256, algorithm: :concurrently unless index_exists?(:drive_files, [:account_id, :sha256], name: :index_drive_files_on_account_id_and_sha256)
    remove_index :drive_files, name: :index_drive_files_on_account_and_sha256_unique, algorithm: :concurrently if index_exists?(:drive_files, [:account_id, :sha256], name: :index_drive_files_on_account_and_sha256_unique)
    remove_column :drive_files, :storage_file_size if column_exists?(:drive_files, :storage_file_size)
  end
end
