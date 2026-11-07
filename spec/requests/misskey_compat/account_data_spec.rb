# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat account export and import endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.drive_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
  end

  def mi(id)
    MisskeyCompat::MiId.encode(id)
  end

  def upload_drive_csv(content, filename: 'following.csv')
    Tempfile.create(['import', '.csv']) do |tempfile|
      tempfile.write(content)
      tempfile.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: 'text/csv')
      CreateDriveFileService.new.call(account: account, user: user, file: upload, generated_export: true)
    end
  end

  describe 'exports' do
    it 'stores the Mastodon following export in the drive' do
      account.follow!(Fabricate(:account, username: 'bob'))

      expect do
        post '/api/i/export-following', params: { i: token }, as: :json
      end.to change(account.drive_files, :count).by(1)

      expect(response).to have_http_status(204)

      drive_file = account.drive_files.last
      expect(drive_file.file_content_type).to eq('text/csv')
      expect(drive_file.file_file_name).to start_with('following_accounts-')
      expect(Paperclip.io_adapters.for(drive_file.file).read).to eq(Export.new(account).to_following_accounts_csv)
    end

    it 'stores blocks, mutes and lists in the drive' do
      account.block!(Fabricate(:account))
      account.mute!(Fabricate(:account))
      Fabricate(:list, account: account).accounts << Fabricate(:account).tap { |member| account.follow!(member) }

      %w(i/export-blocking i/export-mute i/export-user-lists).each do |endpoint|
        post "/api/#{endpoint}", params: { i: token }, as: :json

        expect(response).to have_http_status(204), "#{endpoint}: #{response.body}"
      end

      expect(account.drive_files.map(&:file_file_name)).to contain_exactly(start_with('blocked_accounts-'), start_with('muted_accounts-'), start_with('lists-'))
    end

    it 'reports an export with nothing in it instead of storing an empty file' do
      %w(i/export-following i/export-blocking i/export-mute i/export-user-lists).each do |endpoint|
        post "/api/#{endpoint}", params: { i: token }, as: :json

        expect(response).to have_http_status(400), endpoint
        expect(response.parsed_body.dig('error', 'code')).to eq('NOTHING_TO_EXPORT')
      end

      expect(account.drive_files).to be_empty
    end

    it 'keeps generated exports editable after creation' do
      account.follow!(Fabricate(:account))
      post '/api/i/export-following', params: { i: token }, as: :json

      drive_file = account.drive_files.last
      drive_file.reload.update!(description: 'renamed')

      expect(drive_file.reload.description).to eq('renamed')
    end

    it 'stores the clips export as JSON when clips are enabled' do
      Setting.clips_enabled = true
      Fabricate(:clip, account: account)

      post '/api/i/export-clips', params: { i: token }, as: :json

      expect(response).to have_http_status(204), response.body
      expect(account.drive_files.last).to have_attributes(file_content_type: 'application/json')
    ensure
      Setting.clips_enabled = false
    end

    it 'exports clips only when clips are enabled' do
      Setting.clips_enabled = false

      post '/api/i/export-clips', params: { i: token }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('UNAVAILABLE')
    end

    it 'requires the drive for file exports' do
      Setting.drive_enabled = false

      post '/api/i/export-following', params: { i: token }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('UNAVAILABLE')
    end

    it 'requests a Mastodon archive for notes without the drive' do
      Setting.drive_enabled = false

      expect do
        post '/api/i/export-notes', params: { i: token }, as: :json
      end.to change(user.backups, :count).by(1)

      expect(response).to have_http_status(204)
      expect(BackupWorker).to have_enqueued_sidekiq_job(user.backups.last.id)
    end

    it 'rejects a second archive request inside the Mastodon backup interval' do
      Fabricate(:backup, user: user)

      post '/api/i/export-notes', params: { i: token }, as: :json

      expect(response).to have_http_status(429)
      expect(response.parsed_body.dig('error', 'code')).to eq('RATE_LIMIT_EXCEEDED')
    end

    it 'rejects third-party app tokens' do
      app_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token

      post '/api/i/export-following', params: { i: app_token }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'code')).to eq('ACCESS_DENIED')
    end
  end

  describe 'imports' do
    it 'schedules a Mastodon follow import from a drive file' do
      drive_file = upload_drive_csv("bob@remote.example\nalice@remote.example\n")

      post '/api/i/import-following', params: { i: token, fileId: mi(drive_file.id), withReplies: true }, as: :json

      expect(response).to have_http_status(204), response.body

      bulk_import = account.bulk_imports.last
      expect(bulk_import).to have_attributes(type: 'following', state: 'scheduled', overwrite: false, total_items: 2)
      expect(bulk_import.rows.map { |row| row.data['acct'] }).to contain_exactly('bob@remote.example', 'alice@remote.example')
      expect(BulkImportWorker).to have_enqueued_sidekiq_job(bulk_import.id)
    end

    it 'imports Misskey user list files' do
      drive_file = upload_drive_csv("Friends,bob@remote.example\n", filename: 'user-lists.csv')

      post '/api/i/import-user-lists', params: { i: token, fileId: mi(drive_file.id) }, as: :json

      expect(response).to have_http_status(204), response.body
      expect(account.bulk_imports.last.rows.first.data).to include('list_name' => 'Friends', 'acct' => 'bob@remote.example')
    end

    it 'returns the Misskey error for another account’s file' do
      other_file = CreateDriveFileService.new.call(
        account: Fabricate(:account),
        user: Fabricate(:user),
        file: fixture_file_upload('attachment.jpg', 'image/jpeg')
      )

      post '/api/i/import-muting', params: { i: token, fileId: mi(other_file.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body['error']).to include('code' => 'NO_SUCH_FILE', 'id' => 'e674141e-bd2a-ba85-e616-aefb187c9c2a')
    end

    it 'returns the Misskey error when the stored file is missing' do
      drive_file = upload_drive_csv("bob@remote.example\n")
      File.delete(drive_file.file.path)

      post '/api/i/import-following', params: { i: token, fileId: mi(drive_file.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body['error']).to include('code' => 'NO_SUCH_FILE', 'id' => 'b98644cf-a5ac-4277-a502-0b8054a709a3')
    end

    it 'returns the Misskey error for an empty file' do
      drive_file = upload_drive_csv("bob@remote.example\n")
      drive_file.update_column(:file_file_size, 0)

      post '/api/i/import-blocking', params: { i: token, fileId: mi(drive_file.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body['error']).to include('code' => 'EMPTY_FILE', 'id' => '6f3a4dcc-f060-a707-4950-806fbdbe60d6')
    end

    it 'returns the Misskey error for a file Mastodon cannot import' do
      drive_file = upload_drive_csv("\"unterminated\n")

      post '/api/i/import-following', params: { i: token, fileId: mi(drive_file.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body['error']).to include('code' => 'UNEXPECTED_FILE_TYPE', 'id' => '660f3599-bce0-4f95-9dde-311fd841c183')
      expect(account.bulk_imports).to be_empty
    end
  end

  describe 'policies' do
    it 'advertises the Mastodon-backed imports only while the drive is enabled' do
      post '/api/i', params: { i: token }, as: :json

      expect(response.parsed_body['policies']).to include(
        'canImportFollowing' => true, 'canImportBlocking' => true, 'canImportMuting' => true,
        'canImportUserLists' => true, 'canImportAntennas' => false
      )

      Setting.drive_enabled = false
      post '/api/i', params: { i: token }, as: :json

      expect(response.parsed_body['policies']).to include('canImportFollowing' => false)
    end
  end
end
