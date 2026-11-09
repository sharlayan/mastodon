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

  it 'exports and restores page data and Booklet display preferences without retaining source IDs' do
    series = Fabricate(:page_series, account: account, title: 'Manuals', description: 'A series', displayed: false)
    Fabricate(:page_series, account: account, title: 'Visible', displayed: true)
    page = Fabricate(:page, account: account, name: 'guide', title: 'Guide', content: [{ 'id' => 'text', 'type' => 'text', 'text' => 'Saved text' }])
    page.update!(category: 'notes', page_series: series, series_position: 2)
    series.update!(main_page: page)

    archive_upload(service.export) do |upload|
      account.pages.destroy_all
      account.page_series.destroy_all
      service.import!(upload)
    end

    restored = account.pages.sole
    restored_series = account.page_series.find_by!(title: 'Manuals')
    expect(restored.id).to_not eq(page.id)
    expect(restored_series.id).to_not eq(series.id)
    expect(restored).to have_attributes(name: 'guide', title: 'Guide', category: 'notes', page_series: restored_series, series_position: 2)
    expect(restored_series).to have_attributes(title: 'Manuals', description: 'A series', main_page: restored)
    expect(restored.content).to eq([{ 'id' => 'text', 'type' => 'text', 'text' => 'Saved text' }])
    expect(restored_series).to_not be_displayed
    expect(account.page_series.find_by!(title: 'Visible')).to be_displayed
  end

  it 'restores Booklet cover media with a remapped attachment ID' do
    cover = Fabricate(:media_attachment, account: account)
    Fabricate(:page_series, account: account, cover_media_attachment: cover)

    archive_upload(service.export) do |upload|
      account.page_series.destroy_all
      cover.destroy!
      service.import!(upload)
    end

    restored_cover = account.page_series.sole.cover_media_attachment
    expect(restored_cover).to be_present
    expect(restored_cover.id).to_not eq(cover.id)
  end

  it 'defaults legacy Booklets without a display preference to displayed' do
    archive = zip_archive do |zip|
      zip.get_output_stream(described_class::MANIFEST) do |io|
        io.write({
          format: described_class::FORMAT,
          version: 2,
          pages: [],
          media: [],
          series: [{ id: 'old-series', title: 'Legacy', main_page_id: nil }],
        }.to_json)
      end
    end

    archive_upload(archive) { |upload| service.import!(upload) }

    expect(account.page_series.sole).to be_displayed
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

  it 'restores image blocks without a file or with a file missing from the archive' do
    content = [
      { 'id' => 'empty', 'type' => 'image' },
      { 'id' => 'missing', 'type' => 'image', 'fileId' => '999' },
    ]
    archive = zip_archive do |zip|
      zip.get_output_stream(described_class::MANIFEST) do |io|
        io.write({
          format: described_class::FORMAT,
          version: described_class::VERSION,
          pages: [{ backup_id: 1, title: 'Images', name: 'images', content: content, visibility: 'public' }],
          media: [],
        }.to_json)
      end
    end

    archive_upload(archive) { |upload| service.import!(upload) }

    expect(account.pages.sole.content).to eq([{ 'id' => 'empty', 'type' => 'image' }, { 'id' => 'missing', 'type' => 'image' }])
  end

  it 'ignores counters and main page flags that the exporter does not write' do
    pages = Array.new(2) do |index|
      { backup_id: index, title: "Page #{index}", name: "page-#{index}", content: [], visibility: 'public' }
        .merge(is_main: true, anonymous_views_count: 1000, authenticated_views_count: 2000, likes_count: 3000)
    end
    archive = zip_archive do |zip|
      zip.get_output_stream(described_class::MANIFEST) do |io|
        io.write({ format: described_class::FORMAT, version: described_class::VERSION, pages: pages, media: [] }.to_json)
      end
    end

    archive_upload(archive) { |upload| service.import!(upload) }

    expect(account.pages.where(is_main: true)).to be_empty
    expect(account.pages.pluck(:anonymous_views_count, :authenticated_views_count, :likes_count)).to all(eq([0, 0, 0]))
  end

  it 'restores page media as Drive pointers when pages are limited to Drive files' do
    Setting.pages_drive_only = true
    drive_file = CreateDriveFileService.new.call(account: account, user: account.user, file: fixture_file_upload('attachment.jpg', 'image/jpeg'))
    pointer = drive_file.build_pointer(account).tap(&:save!)
    page = Fabricate(:page, account: account, content: [{ 'id' => 'image', 'type' => 'image', 'fileId' => pointer.id.to_s }], eye_catching_media_attachment: pointer)
    Fabricate(:page_series, account: account, cover_media_attachment: pointer).then { |series| page.update!(page_series: series) }

    archive_upload(service.export) do |upload|
      account.pages.destroy_all
      account.page_series.destroy_all
      pointer.destroy!
      drive_file.destroy!
      service.import!(upload)
    end

    restored = account.pages.sole
    expect(restored.eye_catching_media_attachment).to be_drive_pointer
    expect(restored.content.dig(0, 'fileId')).to eq(restored.eye_catching_media_attachment_id.to_s)
    expect(restored.page_series.cover_media_attachment).to be_drive_pointer
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
