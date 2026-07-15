# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Drive files' do
  let(:account) { Fabricate(:account) }

  before do
    sign_in Fabricate(:admin_user)
  end

  describe 'DELETE /admin/drive/files/destroy_orphaned' do
    it 'deletes orphaned files and preserves attached files' do
      orphan = insert_drive_file
      attached = insert_drive_file
      pointer = attached.build_pointer(account)
      pointer.status = Fabricate(:status, account: account)
      pointer.save!

      delete destroy_orphaned_admin_drive_files_path

      expect(response).to redirect_to(admin_drive_files_path)
      expect(DriveFile).to_not exist(orphan.id)
      expect(DriveFile).to exist(attached.id)
      expect(MediaAttachment).to exist(pointer.id)
    end
  end

  def insert_drive_file
    attributes = {
      account_id: account.id,
      file_content_type: 'image/jpeg',
      file_file_name: 'attachment.jpg',
      file_file_size: 1,
      storage_file_size: 1,
      sha256: SecureRandom.hex(32),
      type: DriveFile.types[:image],
      sensitive: false,
      created_at: Time.current,
      updated_at: Time.current,
    }

    DriveFile.find(DriveFile.insert_all!([attributes]).rows.first.first)
  end
end
