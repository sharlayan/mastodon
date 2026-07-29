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

  def zip_archive(&)
    Tempfile.create(['pages-backup', '.zip']) do |file|
      Zip::File.open(file.path, create: true, &)
      File.binread(file.path)
    end
  end

  it 'exports and restores page data without retaining source IDs' do
    series = Fabricate(:page_series, account: account, title: 'Manuals', description: 'A series')
    page = Fabricate(:page, account: account, name: 'guide', title: 'Guide', content: [{ 'id' => 'text', 'type' => 'text', 'text' => 'Saved text' }])
    page.update!(category: 'notes', page_series: series, series_position: 2)
    series.update!(main_page: page)
    original_page_id = page.id
    original_series_id = series.id

    archive_upload(service.export) do |upload|
      account.pages.destroy_all
      account.page_series.destroy_all
      service.import!(upload)
    end

    restored = account.pages.sole
    restored_series = account.page_series.sole
    expect(restored.id).to_not eq(original_page_id)
    expect(restored_series.id).to_not eq(original_series_id)
    expect(restored).to have_attributes(name: 'guide', title: 'Guide', category: 'notes', page_series: restored_series, series_position: 2)
    expect(restored_series).to have_attributes(title: 'Manuals', description: 'A series', main_page: restored)
    expect(restored.content).to eq([{ 'id' => 'text', 'type' => 'text', 'text' => 'Saved text' }])
  end

  it 'continues to import version 1 archives without series data' do
    archive = zip_archive do |zip|
      zip.get_output_stream(described_class::MANIFEST) do |io|
        io.write({
          format: described_class::FORMAT,
          version: 1,
          pages: [{ title: 'Legacy', name: 'legacy', content: [], visibility: 'public' }],
          media: [],
        }.to_json)
      end
    end

    archive_upload(archive) { |upload| service.import!(upload) }

    expect(account.pages.sole).to have_attributes(title: 'Legacy', page_series: nil)
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

  it 'rejects an oversized manifest before parsing or replacing pages' do
    Fabricate(:page, account: account, name: 'existing')
    archive = zip_archive do |zip|
      zip.get_output_stream(described_class::MANIFEST) do |io|
        io.write({ format: described_class::FORMAT, version: described_class::VERSION, pages: [], media: [], padding: 'a' * (described_class::MAX_MANIFEST_SIZE + 1) }.to_json)
      end
    end

    archive_upload(archive) do |upload|
      expect { service.import!(upload, overwrite: true) }.to raise_error(described_class::InvalidArchive)
    end

    expect(account.pages.find_by(name: 'existing')).to be_present
  end

  it 'rejects an import that exceeds the remaining daily creation limit' do
    account.user.update!(role: Fabricate(:user_role, daily_page_limit: 1))
    pages = Array.new(2) do |index|
      {
        title: "Page #{index}",
        name: "page-#{index}",
        content: [],
        visibility: 'public',
      }
    end
    archive = zip_archive do |zip|
      zip.get_output_stream(described_class::MANIFEST) do |io|
        io.write({ format: described_class::FORMAT, version: described_class::VERSION, pages: pages, media: [] }.to_json)
      end
    end

    archive_upload(archive) do |upload|
      expect { service.import!(upload) }.to raise_error(described_class::InvalidArchive)
    end

    expect(account.pages).to be_empty
  end
end
