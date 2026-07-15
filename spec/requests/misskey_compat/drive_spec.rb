# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat Drive endpoints', :attachment_processing do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.drive_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
  end

  describe 'POST /api/drive/files/create' do
    it 'stores a persistent Drive file whenever the server Drive feature is enabled' do
      expect do
        post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('attachment.jpg', 'image/jpeg'), comment: 'Alt text' }
      end.to change(DriveFile, :count).by(1).and not_change(MediaAttachment, :count)

      expect(response).to have_http_status(200)

      drive_file = account.drive_files.last
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(drive_file.id),
        comment: 'Alt text',
        folderId: nil
      )
      expect(response.parsed_body[:md5]).to match(/\A[0-9a-f]{32}\z/)
      expect(response.parsed_body[:md5]).to eq(Digest::MD5.file(drive_file.file.path(:original)).hexdigest)

      post '/api/notes/create', params: { i: token, text: 'Persistent upload', fileIds: [response.parsed_body[:id]] }, as: :json

      expect(response).to have_http_status(200)
      expect(account.statuses.last.media_attachments.first).to be_drive_pointer
    end

    it 'keeps the legacy upload path when the server Drive feature is disabled' do
      Setting.drive_enabled = false

      expect do
        post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('attachment.jpg', 'image/jpeg') }
      end.to change(MediaAttachment, :count).by(1).and not_change(DriveFile, :count)

      expect(response).to have_http_status(200)
      expect(account.media_attachments.last).to_not be_drive_pointer
    end

    it 'stores a DriveFile without creating a pointer when Drive persistence is enabled' do
      folder = account.drive_folders.create!(name: 'Aria')
      user.update!(settings_attributes: { drive_default_folder_id: folder.id.to_s })

      expect do
        post '/api/drive/files/create', params: {
          i: token,
          file: fixture_file_upload('attachment.jpg', 'image/jpeg'),
          name: 'Aria upload.jpg',
          comment: 'Alt text',
          isSensitive: true,
        }
      end.to change(DriveFile, :count).by(1).and not_change(MediaAttachment, :count)

      expect(response).to have_http_status(200)

      drive_file = account.drive_files.last
      expect(drive_file).to have_attributes(folder_id: folder.id, description: 'Alt text', sensitive: true)
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(drive_file.id),
        name: 'Aria upload.jpg',
        md5: drive_file.md5,
        isSensitive: true,
        folderId: MisskeyCompat::MiId.encode(folder.id),
        userId: MisskeyCompat::MiId.encode(account.id)
      )

      post '/api/notes/create', params: { i: token, text: 'Persistent upload', fileIds: [response.parsed_body[:id]] }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:createdNote, :fileIds)).to eq([MisskeyCompat::MiId.encode(drive_file.id)])
      expect(response.parsed_body.dig(:createdNote, :files, 0, :id)).to eq(MisskeyCompat::MiId.encode(drive_file.id))
      pointer = account.statuses.last.media_attachments.first
      expect(pointer).to be_drive_pointer
      expect(pointer.drive_file_id).to eq(drive_file.id)
    end

    it 'keeps the original image format when original upload is enabled' do
      user.update!(settings_attributes: { drive_upload_original_image: true })

      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('600x400.png', 'image/png') }

      expect(response).to have_http_status(200)
      drive_file = account.drive_files.last
      expect(drive_file.file_content_type).to eq('image/png')
      expect(response.parsed_body[:type]).to eq('image/png')
    end

    it 'compresses images to WebP when original upload is disabled' do
      user.update!(settings_attributes: { drive_upload_original_image: false })

      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('600x400.png', 'image/png') }

      expect(response).to have_http_status(200)
      drive_file = account.drive_files.last
      expect(drive_file.file_content_type).to eq('image/webp')
      expect(drive_file.file_file_name).to end_with('.webp')
      expect(response.parsed_body[:type]).to eq('image/webp')
      expect(response.parsed_body[:url]).to end_with('.webp')
    end

    it 'rejects another account folder without creating a DriveFile' do
      foreign_folder = Fabricate(:account).drive_folders.create!(name: 'Foreign')

      expect do
        post '/api/drive/files/create', params: {
          i: token,
          file: fixture_file_upload('attachment.jpg', 'image/jpeg'),
          folderId: MisskeyCompat::MiId.encode(foreign_folder.id),
        }
      end.to not_change(DriveFile, :count)

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FOLDER')
    end

    it 'rolls back a new pointer when another file id cannot be resolved' do
      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('attachment.jpg', 'image/jpeg') }
      drive_id = response.parsed_body[:id]

      expect do
        post '/api/notes/create', params: { i: token, text: 'Invalid files', fileIds: [drive_id, MisskeyCompat::MiId.encode(999_999)] }, as: :json
      end.to(not_change { MediaAttachment.where.not(drive_file_id: nil).count })

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FILE')
    end

    it 'supports a regular attachment and a DriveFile in the same note' do
      Setting.drive_enabled = false
      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('attachment.jpg', 'image/jpeg') }
      media_id = response.parsed_body[:id]

      Setting.drive_enabled = true
      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('avatar.gif', 'image/gif') }
      drive_id = response.parsed_body[:id]

      post '/api/notes/create', params: { i: token, text: 'Mixed files', fileIds: [media_id, drive_id] }, as: :json

      expect(response).to have_http_status(200)
      attachments = account.statuses.last.ordered_media_attachments
      expect(attachments.map(&:drive_pointer?)).to contain_exactly(false, true)
      expect(response.parsed_body.dig(:createdNote, :fileIds)).to eq([media_id, drive_id])
    end

    it 'attaches a DriveFile pointer to a scheduled note' do
      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('attachment.jpg', 'image/jpeg') }
      drive_id = response.parsed_body[:id]

      post '/api/notes/create', params: {
        i: token,
        text: 'Scheduled file',
        fileIds: [drive_id],
        scheduledAt: 10.minutes.from_now.to_i * 1000,
      }, as: :json

      expect(response).to have_http_status(200)
      pointer = account.scheduled_statuses.last.media_attachments.first
      expect(pointer).to be_drive_pointer
      expect(MisskeyCompat::MiId.encode(pointer.drive_file_id)).to eq(drive_id)
    end

    it 'replaces DriveFile pointers when a note is updated' do
      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('attachment.jpg', 'image/jpeg') }
      first_drive_id = response.parsed_body[:id]
      post '/api/notes/create', params: { i: token, text: 'Before edit', fileIds: [first_drive_id] }, as: :json
      note_id = response.parsed_body.dig(:createdNote, :id)

      post '/api/drive/files/create', params: { i: token, file: fixture_file_upload('avatar.gif', 'image/gif') }
      second_drive_id = response.parsed_body[:id]
      post '/api/notes/update', params: { i: token, noteId: note_id, text: 'After edit', fileIds: [second_drive_id] }, as: :json

      expect(response).to have_http_status(204)
      status = account.statuses.find(MisskeyCompat::MiId.decode(note_id))
      expect(status.ordered_media_attachments.map { |media| MisskeyCompat::MiId.encode(media.drive_file_id) }).to eq([second_drive_id])
    end
  end
end
