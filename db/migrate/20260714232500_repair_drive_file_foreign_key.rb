# frozen_string_literal: true

class RepairDriveFileForeignKey < ActiveRecord::Migration[8.1]
  def up
    foreign_key = drive_file_foreign_key
    return if foreign_key.present? && foreign_key.on_delete.nil?

    safety_assured do
      remove_foreign_key :media_attachments, column: :drive_file_id if foreign_key.present?
      add_foreign_key :media_attachments, :drive_files, column: :drive_file_id, validate: false
    end
  end

  def down
    safety_assured do
      remove_foreign_key :media_attachments, column: :drive_file_id if drive_file_foreign_key.present?
      add_foreign_key :media_attachments, :drive_files, column: :drive_file_id, on_delete: :nullify, validate: false
    end
  end

  private

  def drive_file_foreign_key
    connection.foreign_keys(:media_attachments).find { |foreign_key| foreign_key.to_table == 'drive_files' && foreign_key.column == 'drive_file_id' }
  end
end
