# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat antenna, favorite and custom emoji exports' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:app_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.drive_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
  end

  def drive_json(drive_file)
    JSON.parse(Paperclip.io_adapters.for(drive_file.file).read)
  end

  def upload_drive_json(content)
    Tempfile.create(['antennas', '.json']) do |tempfile|
      tempfile.write(content)
      tempfile.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: 'antennas.json', type: 'application/json')
      CreateDriveFileService.new.call(account: account, user: user, file: upload, generated_export: true)
    end
  end

  it 'queues each export once per Misskey rate limit window and only for native tokens' do
    post '/api/i/export-antennas', params: { i: app_token }, as: :json
    expect(response).to have_http_status(403)

    { 'i/export-antennas' => 'antenna', 'i/export-favorites' => 'favorite', 'export-custom-emojis' => 'customEmoji' }.each do |endpoint, entity|
      post "/api/#{endpoint}", params: { i: token }, as: :json
      expect(response).to have_http_status(204), endpoint
      expect(MisskeyCompatExportWorker).to have_enqueued_sidekiq_job(user.id, entity)

      post "/api/#{endpoint}", params: { i: token }, as: :json
      expect(response).to have_http_status(429), endpoint
    end
  end

  it 'exports representable antennas in the Misskey format and notifies completion' do
    member = Fabricate(:account, username: 'alice', domain: 'remote.example')
    users_antenna = Fabricate(:antenna, account: account, title: 'Users', keywords: %w(cat dog), with_replies: true, any_accounts: false, any_keywords: false)
    users_antenna.antenna_accounts.create!(account: member, exclude: false)
    Fabricate(:antenna, account: account, title: 'Tags only', any_tags: false).antenna_tags.create!(tag: Fabricate(:tag), exclude: false)

    MisskeyCompatExportWorker.new.perform(user.id, 'antenna')

    drive_file = account.drive_files.last
    expect(drive_file.file_file_name).to match(/\Aantennas-[\d-]+\.json\z/)
    expect(drive_json(drive_file)).to eq([{
      'name' => 'Users', 'src' => 'users', 'keywords' => [['cat'], ['dog']], 'excludeKeywords' => [], 'users' => ['alice@remote.example'], 'userListAccts' => nil,
      'caseSensitive' => false, 'localOnly' => false, 'excludeBots' => false, 'withReplies' => true, 'withFile' => false, 'excludeNotesInSensitiveChannel' => false
    }])
    expect(MisskeyNotification.last).to have_attributes(notification_type: 'exportCompleted', data: { 'exportedEntity' => 'antenna', 'fileId' => MisskeyCompat::MiId.encode(drive_file.id) })
  end

  it 'imports Misskey antennas, skipping entries Sharlayan cannot represent, and enforces the antenna limit' do
    Fabricate(:account, username: 'bob')
    base = { 'src' => 'all', 'keywords' => [['news']], 'excludeKeywords' => [], 'users' => [], 'caseSensitive' => false, 'withReplies' => false, 'withFile' => true }
    entries = [
      base.merge('name' => 'News'),
      base.merge('name' => 'Bob', 'src' => 'users', 'users' => ['@bob']),
      base.merge('name' => 'Case', 'caseSensitive' => true),
      base.merge('name' => 'And', 'keywords' => [%w(a b)]),
      base.merge('name' => 'Empty', 'keywords' => [['']]),
      { 'name' => 'Broken' },
    ]
    file = upload_drive_json(JSON.generate(entries))

    post '/api/i/import-antennas', params: { i: token, fileId: MisskeyCompat::MiId.encode(file.id) }, as: :json

    expect(response).to have_http_status(204)
    expect(account.antennas.order(:id).map { |antenna| [antenna.title, antenna.keywords, antenna.with_media_only, antenna.any_accounts] }).to eq([['News', ['news'], true, true], ['Bob', ['news'], true, false]])
    expect(account.antennas.find_by(title: 'Bob').antenna_accounts.map { |aa| aa.account.username }).to eq(['bob'])

    redis.del(redis.keys('rate_limit:*:misskey_compat_import_antennas:*'))
    many = upload_drive_json(JSON.generate(Array.new(Antenna::ANTENNAS_PER_ACCOUNT_LIMIT - 2) { |i| base.merge('name' => "N#{i}") }))
    post '/api/i/import-antennas', params: { i: token, fileId: MisskeyCompat::MiId.encode(many.id) }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'TOO_MANY_ANTENNAS', id: '600917d4-a4cb-4cc5-8ba8-7ac8ea3c7779')
  end

  it 'exports visible favorites with Misskey note fields' do
    author = Fabricate(:account, username: 'carol')
    status = Fabricate(:status, account: author, text: 'hello', spoiler_text: 'cw')
    hidden = Fabricate(:status, account: author, visibility: :private)
    favourite = Fabricate(:favourite, account: account, status: status)
    Fabricate(:favourite, account: account, status: hidden)

    MisskeyCompatExportWorker.new.perform(user.id, 'favorite')

    expect(drive_json(account.drive_files.last)).to match([
                                                            include(
                                                              'id' => MisskeyCompat::MiId.encode(favourite.id),
                                                              'note' => include('id' => MisskeyCompat::MiId.encode(status.id), 'text' => 'hello', 'cw' => 'cw', 'visibility' => 'public', 'poll' => nil, 'user' => include('username' => 'carol', 'host' => nil))
                                                            ),
                                                          ])
  end

  it 'exports enabled local custom emojis as a Misskey zip archive' do
    emoji = Fabricate(:custom_emoji, shortcode: 'blobcat', license: 'CC0', aliases: ['cat'])
    Fabricate(:custom_emoji, shortcode: 'disabled_one', disabled: true)
    Fabricate(:custom_emoji, shortcode: 'remote', domain: 'remote.example')

    MisskeyCompatExportWorker.new.perform(user.id, 'customEmoji')

    drive_file = account.drive_files.last
    expect(drive_file).to have_attributes(file_content_type: 'application/zip')
    Zip::File.open_buffer(Paperclip.io_adapters.for(drive_file.file).read) do |zip|
      meta = JSON.parse(zip.read('meta.json'))
      expect(meta).to include('metaVersion' => 2, 'host' => Rails.configuration.x.local_domain)
      expect(meta['emojis']).to contain_exactly(include('fileName' => 'blobcat.png', 'downloaded' => true, 'emoji' => include('name' => 'blobcat', 'license' => 'CC0', 'aliases' => ['cat'], 'id' => MisskeyCompat::MiId.encode(emoji.id))))
      expect(zip.find_entry('blobcat.png').size).to be > 0
    end
    expect(MisskeyNotification.last.data).to include('exportedEntity' => 'customEmoji')
  end
end
