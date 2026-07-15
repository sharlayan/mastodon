# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat Drive RPC', :attachment_processing do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.drive_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
  end

  describe 'file RPC' do
    let!(:file) { DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg')).tap { |item| item.update!(md5: '0123456789abcdef') } }

    it 'lists, shows, updates, finds, and moves owned files with MiId fields' do
      folder = account.drive_folders.create!(name: 'Pictures')

      rpc_post 'drive/files', folderId: nil, limit: 30
      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([mi_id(file.id)])

      rpc_post 'drive/files/show', fileId: mi_id(file.id)
      expect(response.parsed_body).to include(id: mi_id(file.id), md5: file.md5, folderId: nil)

      rpc_post 'drive/files/update', fileId: mi_id(file.id), folderId: mi_id(folder.id), name: 'Portrait', comment: 'Alt', isSensitive: true
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(name: 'Portrait', comment: 'Alt', isSensitive: true, folderId: mi_id(folder.id))

      rpc_post 'drive/files/find', name: 'Portrait', folderId: mi_id(folder.id)
      expect(response.parsed_body.pluck(:id)).to eq([mi_id(file.id)])

      rpc_post 'drive/files/move-bulk', fileIds: [mi_id(file.id)], folderId: nil
      expect(response).to have_http_status(204)
      expect(file.reload.folder_id).to be_nil
    end

    it 'supports hash lookup and returns a bare existence boolean' do
      rpc_post 'drive/files/find-by-hash', md5: file.md5
      expect(response.parsed_body.pluck(:id)).to eq([mi_id(file.id)])

      rpc_post 'drive/files/check-existence', md5: file.md5
      expect(response.parsed_body).to be(true)

      rpc_post 'drive/files/check-existence', md5: 'missing'
      expect(response.parsed_body).to be(false)
    end

    it 'paginates beyond Aria default page size with untilId' do
      Array.new(40) { insert_drive_file }

      rpc_post 'drive/files', folderId: nil, limit: 30
      first_page = response.parsed_body.pluck(:id)
      rpc_post 'drive/files', folderId: nil, limit: 30, untilId: first_page.last
      second_page = response.parsed_body.pluck(:id)

      expect(first_page.size).to eq(30)
      expect(second_page.size).to eq(11)
      expect(first_page & second_page).to be_empty
    end

    it 'returns every visible note attached through Drive pointers' do
      statuses = Array.new(2) do
        status = Fabricate(:status, account: account)
        file.build_pointer(account).tap { |pointer| pointer.update!(status_id: status.id) }
        status
      end

      rpc_post 'drive/files/attached-notes', fileId: mi_id(file.id)

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to match_array(statuses.map { |status| mi_id(status.id) })
    end

    it 'rejects deletion while attached and deletes an unused file' do
      status = Fabricate(:status, account: account)
      file.build_pointer(account).tap { |pointer| pointer.update!(status_id: status.id) }

      rpc_post 'drive/files/delete', fileId: mi_id(file.id)
      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig(:error, :code)).to eq('ATTACHED')

      unused = DriveFile.create!(account: account, file: attachment_fixture('avatar.gif'))
      rpc_post 'drive/files/delete', fileId: mi_id(unused.id)
      expect(response).to have_http_status(204)
      expect(DriveFile.exists?(unused.id)).to be(false)
    end

    it 'enqueues URL uploads with the default folder' do
      folder = account.drive_folders.create!(name: 'Imports')
      user.update!(settings_attributes: { drive_default_folder_id: folder.id.to_s })
      allow(DriveFileFromURLWorker).to receive(:perform_async)

      rpc_post 'drive/files/upload-from-url', url: 'https://example.com/image.jpg', comment: 'Remote', isSensitive: true

      expect(response).to have_http_status(204)
      expect(DriveFileFromURLWorker).to have_received(:perform_async).with(account.id, 'https://example.com/image.jpg', {
        'folder_id' => folder.id.to_s,
        'sensitive' => true,
        'description' => 'Remote',
      })
    end

    it 'hides files owned by another account' do
      foreign_file = DriveFile.create!(account: Fabricate(:account), file: attachment_fixture('avatar.gif'))

      rpc_post 'drive/files/show', fileId: mi_id(foreign_file.id)

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FILE')
    end
  end

  describe 'folder RPC' do
    it 'creates, lists, shows, updates, finds, and deletes folders' do
      rpc_post 'drive/folders/create', name: 'Parent', parentId: nil
      parent_id = response.parsed_body[:id]
      expect(response).to have_http_status(200)

      rpc_post 'drive/folders/create', name: 'Child', parentId: parent_id
      child_id = response.parsed_body[:id]

      rpc_post 'drive/folders', folderId: nil, limit: 30
      expect(response.parsed_body.pluck(:id)).to eq([parent_id])

      rpc_post 'drive/folders', folderId: parent_id, limit: 30
      expect(response.parsed_body.pluck(:id)).to eq([child_id])

      rpc_post 'drive/folders/show', folderId: parent_id
      expect(response.parsed_body).to include(id: parent_id, foldersCount: 1, filesCount: 0, parentId: nil)

      rpc_post 'drive/folders/update', folderId: child_id, name: 'Moved', parentId: nil
      expect(response.parsed_body).to include(id: child_id, name: 'Moved', parentId: nil)

      rpc_post 'drive/folders/find', name: 'Moved', parentId: nil
      expect(response.parsed_body.pluck(:id)).to eq([child_id])

      rpc_post 'drive/folders/delete', folderId: child_id
      expect(response).to have_http_status(204)
      expect(account.drive_folders.exists?(MisskeyCompat::MiId.decode(child_id))).to be(false)
    end

    it 'includes the complete parent chain in folder details' do
      grandparent = account.drive_folders.create!(name: 'Grandparent')
      parent = account.drive_folders.create!(name: 'Parent', parent: grandparent)
      child = account.drive_folders.create!(name: 'Child', parent: parent)

      rpc_post 'drive/folders/show', folderId: mi_id(child.id)

      expect(response.parsed_body.dig(:parent, :id)).to eq(mi_id(parent.id))
      expect(response.parsed_body.dig(:parent, :parent, :id)).to eq(mi_id(grandparent.id))
    end

    it 'rejects another account parent folder' do
      foreign = Fabricate(:account).drive_folders.create!(name: 'Foreign')

      rpc_post 'drive/folders/create', name: 'Invalid', parentId: mi_id(foreign.id)

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FOLDER')
    end
  end

  it 'requires the native Drive feature for resource RPC' do
    Setting.drive_enabled = false

    rpc_post 'drive/files'

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('UNAVAILABLE')
  end

  it 'requires write scope for Drive mutations' do
    read_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token
    file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

    post '/api/drive/files/update', params: { i: read_token, fileId: mi_id(file.id), name: 'Denied' }, as: :json

    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    expect(file.reload.display_name).to_not eq('Denied')
  end

  it 'advertises exactly the implemented Drive HTTP endpoints while Drive is enabled' do
    post '/api/endpoints', as: :json

    drive_endpoints = response.parsed_body.grep(%r{\Adrive/})
    expected = %w(
      drive/files
      drive/files/attached-notes
      drive/files/check-existence
      drive/files/create
      drive/files/delete
      drive/files/find
      drive/files/find-by-hash
      drive/files/move-bulk
      drive/files/show
      drive/files/update
      drive/files/upload-from-url
      drive/folders
      drive/folders/create
      drive/folders/delete
      drive/folders/find
      drive/folders/show
      drive/folders/update
    )
    expect(drive_endpoints).to match_array(expected)
  end

  it 'advertises only the legacy upload endpoint while the native Drive feature is disabled' do
    Setting.drive_enabled = false

    post '/api/endpoints', as: :json

    expect(response.parsed_body.grep(%r{\Adrive(?:/|\z)})).to contain_exactly('drive/files/create')

    post '/api/endpoint', params: { endpoint: 'drive/files/create' }, as: :json
    expect(response).to have_http_status(200)

    post '/api/endpoint', params: { endpoint: 'drive/files/show' }, as: :json
    expect(response).to have_http_status(404)
  end

  def rpc_post(endpoint, params = {})
    post "/api/#{endpoint}", params: { i: token }.merge(params), as: :json
  end

  def mi_id(id)
    MisskeyCompat::MiId.encode(id)
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
