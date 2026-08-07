# frozen_string_literal: true

class AddDriveAccessKeyToMediaAttachments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MediaAttachment < ApplicationRecord; end

  def up
    add_column :media_attachments, :drive_access_key, :string unless column_exists?(:media_attachments, :drive_access_key)

    backfill_drive_access_keys

    add_index :media_attachments, :drive_access_key, unique: true, where: 'drive_access_key IS NOT NULL', algorithm: :concurrently unless index_exists?(:media_attachments, :drive_access_key, unique: true, where: 'drive_access_key IS NOT NULL')
  end

  def down
    remove_index :media_attachments, :drive_access_key, algorithm: :concurrently if index_exists?(:media_attachments, :drive_access_key)
    remove_column :media_attachments, :drive_access_key if column_exists?(:media_attachments, :drive_access_key)
  end

  private

  def backfill_drive_access_keys
    MediaAttachment.reset_column_information

    MediaAttachment.where.not(drive_file_id: nil).where(drive_access_key: nil).find_each do |attachment|
      attachment.update_column(:drive_access_key, SecureRandom.urlsafe_base64(32))
    end
  end
end
