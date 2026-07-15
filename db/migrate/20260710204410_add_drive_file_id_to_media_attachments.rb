# frozen_string_literal: true

class AddDriveFileIdToMediaAttachments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :media_attachments, :drive_file_id, :bigint, null: true unless column_exists?(:media_attachments, :drive_file_id)

    add_index :media_attachments, :drive_file_id, algorithm: :concurrently, where: 'drive_file_id IS NOT NULL' unless index_exists?(:media_attachments, :drive_file_id)

    add_foreign_key :media_attachments, :drive_files, column: :drive_file_id, validate: false unless foreign_key_exists?(:media_attachments, :drive_files)
  end

  def down
    remove_foreign_key :media_attachments, column: :drive_file_id if foreign_key_exists?(:media_attachments, :drive_files)
    remove_index :media_attachments, :drive_file_id, algorithm: :concurrently if index_exists?(:media_attachments, :drive_file_id)
    remove_column :media_attachments, :drive_file_id if column_exists?(:media_attachments, :drive_file_id)
  end
end
