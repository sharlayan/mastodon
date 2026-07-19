# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::PageBackupService do
  let(:account) { Fabricate(:account) }
  let(:service) { described_class.new(account) }

  def archive_upload(contents)
    Tempfile.create(['pages-backup', '.zip']) do |file|
      file.binmode
      file.write(contents)
      file.flush
      file.rewind
      yield ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'pages-backup.zip', type: 'application/zip')
    end
  end

  it 'exports and restores page data without retaining source IDs' do
    page = Fabricate(:page, account: account, name: 'guide', title: 'Guide', content: [{ 'id' => 'text', 'type' => 'text', 'text' => 'Saved text' }])
    page.update!(visibility: 'private', category: 'notes')

    archive_upload(service.export) do |upload|
      account.pages.destroy_all
      service.import!(upload)
    end

    restored = account.pages.sole
    expect(restored).to have_attributes(name: 'guide', title: 'Guide', visibility: 'private', category: 'notes')
    expect(restored.content).to eq([{ 'id' => 'text', 'type' => 'text', 'text' => 'Saved text' }])
  end

  it 'restores page media with remapped attachment IDs' do
    attachment = Fabricate(:media_attachment, account: account)
    Fabricate(:page, account: account, content: [{ 'id' => 'image', 'type' => 'image', 'fileId' => attachment.id.to_s }], eye_catching_media_attachment: attachment)

    archive_upload(service.export) do |upload|
      account.pages.destroy_all
      attachment.destroy!
      service.import!(upload)
    end

    restored = account.pages.sole
    expect(restored.eye_catching_media_attachment).to be_present
    expect(restored.content.dig(0, 'fileId')).to eq(restored.eye_catching_media_attachment_id.to_s)
  end

  it 'rejects a non-page archive' do
    archive_upload('not a zip') do |upload|
      expect { service.import!(upload) }.to raise_error(described_class::InvalidArchive)
    end
  end
end
