# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DriveFileFromURLWorker do
  subject(:worker) { worker_class.new }

  let(:account) { Fabricate(:user).account }
  let(:folder) { account.drive_folders.create!(name: 'Imports') }
  let(:worker_class) do
    Class.new(described_class) do
      private

      def download_to(candidate, _url)
        assign_downloaded_file(candidate, Rails.root.join('spec', 'fixtures', 'files', 'avatar.gif').open)
      end
    end
  end

  describe '.enqueue' do
    it 'suppresses duplicate account and URL jobs while one is queued' do
      allow(described_class).to receive(:perform_async)
      key = described_class.deduplication_key(account.id, 'https://example.com/image.jpg')

      expect(described_class.enqueue(account.id, 'https://example.com/image.jpg')).to be true
      expect(described_class.enqueue(account.id, 'https://example.com/image.jpg')).to be false
      expect(described_class).to have_received(:perform_async).once
    ensure
      RedisConnection.with { |redis| redis.del(key) } if key
    end
  end

  it 'persists URL upload metadata used by Aria polling' do
    worker.perform(account.id, 'https://example.com/avatar.gif', {
      'folder_id' => folder.id.to_s,
      'sensitive' => true,
      'description' => 'aria-marker',
    })

    file = account.drive_files.find_by!(description: 'aria-marker')
    expect(file).to have_attributes(folder: folder, sensitive: true)
    expect(file.sha256).to be_present
    expect(file.md5).to be_present
  end

  it 'promotes a deduplicated upload so Aria can find its marker with limit one' do
    digest = Digest::SHA256.file(Rails.root.join('spec', 'fixtures', 'files', 'avatar.gif')).hexdigest
    existing = DriveFile.create!(account: account, file: attachment_fixture('avatar.gif'), sha256: digest, created_at: 2.days.ago)
    newer = DriveFile.create!(account: account, file: attachment_fixture('600x400.jpeg'), created_at: 1.day.ago)

    expect do
      worker.perform(account.id, 'https://example.com/avatar.gif', {
        'folder_id' => folder.id.to_s,
        'sensitive' => true,
        'description' => 'aria-marker',
      })
    end.to_not change(account.drive_files, :count)

    expect(existing.reload).to have_attributes(folder: folder, sensitive: true, description: 'aria-marker')
    expect(existing.created_at).to be > newer.created_at
    expect(account.drive_files.where(folder: folder).ordered.first).to eq(existing)
  end

  it 'defaults an omitted sensitive option to false' do
    worker.perform(account.id, 'https://example.com/avatar.gif')

    expect(account.drive_files.sole).to_not be_sensitive
  end

  it 'treats an explicit nil sensitive option as false' do
    worker.perform(account.id, 'https://example.com/avatar.gif', { 'sensitive' => nil })

    expect(account.drive_files.sole).to_not be_sensitive
  end

  it 'preserves sensitive and description metadata for a matching existing file unless sensitive is explicitly false' do
    digest = Digest::SHA256.file(Rails.root.join('spec', 'fixtures', 'files', 'avatar.gif')).hexdigest
    existing = DriveFile.create!(account: account, file: attachment_fixture('avatar.gif'), sha256: digest, sensitive: true, description: 'kept')

    expect do
      worker.perform(account.id, 'https://example.com/avatar.gif', { 'sensitive' => nil })
    end.to_not change(account.drive_files, :count)
    expect(existing.reload).to be_sensitive

    worker.perform(account.id, 'https://example.com/avatar.gif')
    expect(existing.reload).to be_sensitive

    worker.perform(account.id, 'https://example.com/avatar.gif', {})
    expect(existing.reload.description).to eq 'kept'

    worker.perform(account.id, 'https://example.com/avatar.gif', { 'sensitive' => false })
    expect(existing.reload).to_not be_sensitive
  end

  context 'when the downloaded image is processed', :attachment_processing do
    let(:image_path) { Rails.root.join('spec', 'fixtures', 'files', '600x400.png') }
    let(:worker_class) { described_class }

    before do
      account.user.update!(settings_attributes: { drive_upload_original_image: false })
      stub_request(:get, 'https://example.com/600x400.png').to_return(body: File.binread(image_path), headers: { 'Content-Type' => 'image/png' })
    end

    it 'stores the hashes of the downloaded bytes before WebP conversion' do
      worker.perform(account.id, 'https://example.com/600x400.png', { 'sensitive' => false })

      file = account.drive_files.sole
      expect(file.file_content_type).to eq('image/webp')
      expect(file.sha256).to eq(Digest::SHA256.file(image_path).hexdigest)
      expect(file.md5).to eq(Digest::MD5.file(image_path).hexdigest)
    end

    it 'deduplicates a URL upload against the same image uploaded directly' do
      upload = Rack::Test::UploadedFile.new(image_path, 'image/png')
      existing = CreateDriveFileService.new.call(account: account, user: account.user, file: upload)

      expect do
        worker.perform(account.id, 'https://example.com/600x400.png', { 'sensitive' => false })
      end.to_not change(account.drive_files, :count)

      expect(account.drive_files.sole).to eq(existing)
    end
  end

  it 'uses the quota configured for the account role' do
    account.user.role.update!(drive_quota: 1)
    Setting.drive_quota = 100
    existing = DriveFile.create!(account: account, file: attachment_fixture('600x400.jpeg'))
    existing.update_column(:storage_file_size, 1.megabyte)

    expect do
      worker.perform(account.id, 'https://example.com/avatar.gif', { 'description' => 'over-quota' })
    end.to_not change(account.drive_files, :count)

    expect(account.drive_files).to_not exist(description: 'over-quota')
  end
end
