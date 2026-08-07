# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive files API' do
  include_context 'with API authentication', oauth_scopes: 'read write:media'

  before do
    Setting.drive_enabled = true
  end

  describe 'GET /api/v1/drive/files' do
    subject do
      get '/api/v1/drive/files', headers: headers, params: params
    end

    let(:params) { { folder_id: '' } }
    let(:folder) { user.account.drive_folders.create!(name: 'Nested') }

    it 'only returns files in the explicitly requested root folder' do
      root_file = insert_drive_file
      insert_drive_file(folder_id: folder.id)

      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(root_file.id.to_s)
    end

    it 'provides a next link that preserves the root folder filter' do
      files = Array.new(41) { insert_drive_file }

      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(40)
      expect(response.headers['Link']).to include('rel="next"', 'folder_id=')

      get URI.parse(response.headers['Link'][/<([^>]+)>; rel="next"/, 1]).request_uri, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(files.first.id.to_s)
    end

    it 'flags files that no status uses as orphaned' do
      attached_file = insert_drive_file
      unused_file = insert_drive_file
      attach_to_status(attached_file)

      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.index_by { |file| file[:id] }.transform_values { |file| file[:orphaned] })
        .to eq(attached_file.id.to_s => false, unused_file.id.to_s => true)
    end

    it 'flags files used by pages as not orphaned' do
      page_file = insert_drive_file
      unused_file = insert_drive_file
      attach_to_page(page_file, eye_catching: true)

      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.index_by { |file| file[:id] }.transform_values { |file| file[:orphaned] })
        .to eq(page_file.id.to_s => false, unused_file.id.to_s => true)
    end

    context 'when filtering to orphaned files' do
      let(:params) { { orphaned: true } }

      it 'returns unused files from every folder and excludes attached ones' do
        attached_file = insert_drive_file
        root_file = insert_drive_file
        nested_file = insert_drive_file(folder_id: folder.id)
        attach_to_status(attached_file)

        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body.pluck(:id)).to contain_exactly(root_file.id.to_s, nested_file.id.to_s)
      end
    end
  end

  describe 'POST /api/v1/drive/files', :attachment_processing do
    it 'returns the existing file for a duplicate upload' do
      post_drive_file
      first_id = response.parsed_body[:id]

      expect { post_drive_file }.to_not change(DriveFile, :count)
      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(first_id)
    end

    it 'keeps the name of the uploaded file as the display name, apart from the stored file name' do
      post_drive_file(name: '설정 자료.jpg')

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('설정 자료.jpg')
      expect(response.parsed_body[:file_name]).to eq(DriveFile.find(response.parsed_body[:id]).file_file_name)
      expect(response.parsed_body[:file_name]).to_not eq('설정 자료.jpg')
    end

    it 'falls back to the uploaded file name when no display name is given' do
      post_drive_file

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('attachment.jpg')
    end

    it 'does not keep an uploaded name when that preference is disabled' do
      user.update!(settings_attributes: { drive_keep_original_filename: false })

      post_drive_file(name: 'Portrait.jpg')

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq(response.parsed_body[:file_name])
    end

    it 'does not overwrite a display name the user picked when the same file is uploaded again' do
      post_drive_file
      put "/api/v1/drive/files/#{response.parsed_body[:id]}", headers: headers, params: { name: 'Portrait' }

      post_drive_file(name: 'attachment.jpg')

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('Portrait')
    end

    it 'uses the user default folder when the request omits folder_id' do
      folder = user.account.drive_folders.create!(name: 'Uploads')
      user.update!(settings_attributes: { drive_default_folder_id: folder.id.to_s })

      post_drive_file

      expect(response).to have_http_status(200)
      expect(DriveFile.find(response.parsed_body[:id]).folder_id).to eq(folder.id)
    end

    it 'prefers an explicitly requested folder over the user default folder' do
      default_folder = user.account.drive_folders.create!(name: 'Uploads')
      requested_folder = user.account.drive_folders.create!(name: 'Requested')
      user.update!(settings_attributes: { drive_default_folder_id: default_folder.id.to_s })

      post_drive_file(folder_id: requested_folder.id)

      expect(response).to have_http_status(200)
      expect(DriveFile.find(response.parsed_body[:id]).folder_id).to eq(requested_folder.id)
    end

    it 'falls back to the root when the stored default folder is invalid' do
      user.update!(settings_attributes: { drive_default_folder_id: '999999' })

      post_drive_file

      expect(response).to have_http_status(200)
      expect(DriveFile.find(response.parsed_body[:id]).folder_id).to be_nil
    end

    it 'rejects a file type the administrator has not allowed' do
      expect { post_text_file }.to_not change(DriveFile, :count)

      expect(response).to have_http_status(422)
    end

    it 'accepts a file type the administrator has allowed' do
      Setting.drive_allowed_extensions = 'txt, pdf'

      expect { post_text_file }.to change(DriveFile, :count).by(1)

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(type: 'unknown', content_type: 'text/plain')
    end

    it 'rejects a file larger than the per-file limit' do
      Setting.drive_max_file_size = 1

      expect { post_audio_file }.to_not change(DriveFile, :count)

      expect(response).to have_http_status(422)
    end

    it 'charges quota using the stored processed size' do
      Setting.drive_quota = 1
      insert_drive_file(storage_file_size: 1.megabyte)

      expect { post_drive_file }.to_not change(DriveFile, :count)
      expect(response).to have_http_status(422)
      expect(response.parsed_body[:error]).to eq('Drive storage quota exceeded')
    end

    it 'uses the quota configured for the user role' do
      user.role.update!(drive_quota: 1)
      Setting.drive_quota = 100
      insert_drive_file(storage_file_size: 1.megabyte)

      expect { post_drive_file }.to_not change(DriveFile, :count)
      expect(response).to have_http_status(422)
      expect(response.parsed_body[:error]).to eq('Drive storage quota exceeded')
    end
  end

  describe 'PUT /api/v1/drive/files/:id' do
    let(:file) { insert_drive_file }

    it 'renames the file for display without renaming the stored file' do
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { name: '설정 자료' }

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(name: '설정 자료', file_name: 'attachment.jpg')
      expect(file.reload.file_file_name).to eq('attachment.jpg')
    end

    it 'restores the stored file name when the display name is cleared' do
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { name: '설정 자료' }
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { name: '' }

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('attachment.jpg')
      expect(file.reload.custom_name).to be_nil
    end

    it 'caps the display name at 128 characters' do
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { name: 'ㄱ' * 200 }

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('ㄱ' * 128)
      expect(file.reload.custom_name.name.length).to eq(128)
    end

    it 'strips control characters from the display name' do
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { name: "port\u0000rait\nfile" }

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('port rait file')
    end

    it 'keeps the display name when other metadata changes' do
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { name: '설정 자료' }
      put "/api/v1/drive/files/#{file.id}", headers: headers, params: { description: 'A portrait' }

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(name: '설정 자료', description: 'A portrait')
    end
  end

  describe 'DELETE /api/v1/drive/files/:id' do
    it 'refuses to delete a file used by a page image block' do
      drive_file = insert_drive_file
      pointer = attach_to_page(drive_file)

      expect do
        delete "/api/v1/drive/files/#{drive_file.id}", headers: headers
      end.to not_change(DriveFile, :count).and not_change(MediaAttachment, :count)

      expect(response).to have_http_status(422)
      expect(response.parsed_body[:code]).to eq('ATTACHED')
      expect(DriveFile).to exist(drive_file.id)
      expect(MediaAttachment).to exist(pointer.id)
    end
  end

  describe 'POST /api/v1/drive/files/:id/transfer_to_posts', :attachment_processing do
    let(:drive_file) { user.account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
    let(:status) { Fabricate(:status, account: user.account) }
    let(:scheduled_status) { Fabricate(:scheduled_status, account: user.account) }

    it 'copies attached pointers to regular media attachments and removes the Drive file' do
      status_pointer = drive_file.build_pointer(user.account).tap { |media| media.update!(status: status) }
      scheduled_pointer = drive_file.build_pointer(user.account).tap { |media| media.update!(scheduled_status: scheduled_status) }
      access_key = status_pointer.drive_access_key
      original_bytes = File.binread(drive_file.file.path(:original))
      preview_bytes = File.binread(drive_file.file.path(:small))

      expect do
        post "/api/v1/drive/files/#{drive_file.id}/transfer_to_posts", headers: headers
      end.to change(DriveFile, :count).by(-1).and not_change(MediaAttachment, :count)

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('transferred' => 2)

      expect(status_pointer.reload).to have_attributes(drive_file_id: nil, status_id: status.id)
      expect(File.binread(status_pointer.file.path(:original))).to eq(original_bytes)
      expect(File.binread(status_pointer.file.path(:small))).to eq(preview_bytes)
      expect(scheduled_pointer.reload).to have_attributes(drive_file_id: nil, scheduled_status_id: scheduled_status.id)
      expect(File.binread(scheduled_pointer.file.path(:original))).to eq(original_bytes)

      get drive_media_path(access_key, :original)
      expect(response).to have_http_status(200)
      expect(response.body.b).to eq(original_bytes)
    end

    it 'rejects a Drive file that is not attached to a post' do
      post "/api/v1/drive/files/#{drive_file.id}/transfer_to_posts", headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body[:code]).to eq('NOT_ATTACHED')
      expect(drive_file.reload).to be_persisted
    end

    it 'rejects a Drive file used by a page even when it is also attached to a post' do
      status_pointer = drive_file.build_pointer(user.account).tap { |media| media.update!(status: status) }
      page_pointer = attach_to_page(drive_file)

      expect do
        post "/api/v1/drive/files/#{drive_file.id}/transfer_to_posts", headers: headers
      end.to not_change(DriveFile, :count).and not_change(MediaAttachment, :count)

      expect(response).to have_http_status(422)
      expect(response.parsed_body[:code]).to eq('PAGE_ATTACHED')
      expect(status_pointer.reload.drive_file_id).to eq(drive_file.id)
      expect(page_pointer.reload.drive_file_id).to eq(drive_file.id)
    end

    it 'does not expose another account file' do
      foreign_file = Fabricate(:account).drive_files.create!(file: attachment_fixture('attachment.jpg'))

      post "/api/v1/drive/files/#{foreign_file.id}/transfer_to_posts", headers: headers

      expect(response).to have_http_status(404)
    end
  end

  describe 'file ownership' do
    let(:foreign_file) { insert_drive_file(account_id: Fabricate(:account).id) }

    it 'does not show another account file' do
      get "/api/v1/drive/files/#{foreign_file.id}", headers: headers

      expect(response).to have_http_status(404)
    end

    it 'does not attach another account file' do
      expect do
        post "/api/v1/drive/files/#{foreign_file.id}/attach", headers: headers
      end.to_not change(MediaAttachment, :count)

      expect(response).to have_http_status(404)
    end
  end

  def post_drive_file(name: nil, folder_id: nil)
    params = { file: fixture_file_upload('attachment.jpg', 'image/jpeg') }
    params[:name] = name if name.present?
    params[:folder_id] = folder_id if folder_id.present?

    post '/api/v1/drive/files', headers: headers, params: params
  end

  def post_text_file
    post '/api/v1/drive/files', headers: headers, params: { file: fixture_file_upload('bookmark-imports.txt', 'text/plain') }
  end

  def post_audio_file
    post '/api/v1/drive/files', headers: headers, params: { file: fixture_file_upload('boop.mp3', 'audio/mp3') }
  end

  def attach_to_status(drive_file)
    status = Fabricate(:status, account: user.account)
    drive_file.build_pointer(user.account).tap { |media| media.update!(status_id: status.id) }
  end

  def attach_to_page(drive_file, eye_catching: false)
    pointer = drive_file.build_pointer(user.account).tap(&:save!)
    attributes = if eye_catching
                   { eye_catching_media_attachment: pointer }
                 else
                   { content: [{ id: 'image', type: 'image', fileId: pointer.id.to_s }] }
                 end
    Fabricate(:page, account: user.account, **attributes)
    pointer
  end

  def insert_drive_file(account_id: user.account.id, folder_id: nil, storage_file_size: 1)
    attributes = {
      account_id: account_id,
      folder_id: folder_id,
      file_content_type: 'image/jpeg',
      file_file_name: 'attachment.jpg',
      file_file_size: 1,
      storage_file_size: storage_file_size,
      sha256: SecureRandom.hex(32),
      type: DriveFile.types[:image],
      sensitive: false,
      created_at: Time.current,
      updated_at: Time.current,
    }

    DriveFile.find(DriveFile.insert_all!([attributes]).rows.first.first)
  end
end
