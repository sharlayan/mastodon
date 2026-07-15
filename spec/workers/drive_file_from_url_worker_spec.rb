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
        candidate.file = Rails.root.join('spec', 'fixtures', 'files', 'avatar.gif').open
        true
      end
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
