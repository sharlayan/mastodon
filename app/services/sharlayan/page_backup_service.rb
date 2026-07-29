# frozen_string_literal: true

class Sharlayan::PageBackupService
  FORMAT = 'sharlayan-pages-backup'
  VERSION = 2
  SUPPORTED_VERSIONS = [1, VERSION].freeze
  MANIFEST = 'pages.json'
  MAX_ARCHIVE_SIZE = 100.megabytes
  MAX_MEDIA_SIZE = 100.megabytes
  MAX_MANIFEST_SIZE = 5.megabytes
  MAX_ARCHIVE_ENTRIES = 10_000
  MAX_UNCOMPRESSED_SIZE = MAX_MANIFEST_SIZE + MAX_MEDIA_SIZE
  MAX_SERIES = 500

  class InvalidArchive < StandardError; end

  def initialize(account)
    @account = account
  end

  def export
    Tempfile.create(['pages-backup', '.zip']) do |file|
      Zip::File.open(file.path, create: true) { |zip| write_to_zip(zip) }
      File.binread(file.path)
    end
  end

  def write_to_zip(zip)
    attachments = page_attachments
    paths = attachments.index_with { |attachment| media_path(attachment) }

    zip.get_output_stream(MANIFEST) { |io| io.write(manifest(paths).to_json) }

    paths.each do |attachment, path|
      source = attachment.drive_pointer? ? attachment.drive_file.file : attachment.file
      zip.get_output_stream(path) { |io| copy_attachment(source, io) }
    end
  end

  def import!(upload, overwrite: false)
    raise InvalidArchive if upload.size > MAX_ARCHIVE_SIZE

    Zip::File.open(upload.path) do |zip|
      manifest_entry = validate_archive!(zip)
      data = JSON.parse(read_entry(manifest_entry, MAX_MANIFEST_SIZE))
      validate_manifest!(data)

      ApplicationRecord.transaction do
        @account.lock!
        if overwrite
          @account.pages.destroy_all
          @account.page_series.destroy_all
        end
        validate_import_capacity!(data.fetch('pages').size)
        media_ids = import_media!(zip, data.fetch('media'))
        series_ids = import_series!(data.fetch('series', []))
        page_ids = data.fetch('pages').to_h do |attributes|
          page = import_page!(attributes, media_ids, series_ids)
          [attributes['backup_id'].to_s, page.id]
        end
        restore_series_mains!(data.fetch('series', []), series_ids, page_ids)
      end
    end
  rescue Zip::Error, JSON::ParserError, KeyError, ActiveRecord::RecordInvalid => e
    raise InvalidArchive, e.message
  end

  private

  def manifest(paths)
    {
      format: FORMAT,
      version: VERSION,
      series: @account.page_series.reorder(:id).map { |series| series_attributes(series) },
      pages: @account.pages.reorder(:id).map { |page| page_attributes(page) },
      media: paths.map { |attachment, path| media_attributes(attachment, path) },
    }
  end

  def page_attributes(page)
    page.slice('title', 'name', 'summary', 'category', 'content', 'align_center', 'hide_title_when_pinned', 'font', 'visibility', 'access_password_digest', 'series_position')
      .merge(
        'backup_id' => page.id,
        'page_series_id' => page.page_series_id,
        'eye_catching_media_attachment_id' => page.eye_catching_media_attachment_id
      )
  end

  def series_attributes(series)
    {
      id: series.id,
      title: series.title,
      description: series.description,
      main_page_id: series.main_page_id,
    }
  end

  def media_attributes(attachment, path)
    {
      id: attachment.id,
      path: path,
      description: attachment.description,
      type: attachment.type,
      content_type: attachment.file_content_type,
    }
  end

  def page_attachments
    ids = @account.pages.flat_map { |page| page.attached_media.ids + [page.eye_catching_media_attachment_id] }.compact.uniq
    @account.media_attachments.where(id: ids).to_a
  end

  def media_path(attachment)
    "page_media/#{attachment.id}/#{attachment.file_file_name}"
  end

  def copy_attachment(attachment, output)
    adapter = Paperclip.io_adapters.for(attachment)
    loop do
      buffer = adapter.read
      break if buffer.blank?

      output.write(buffer)
    end
  end

  def validate_manifest!(data)
    raise InvalidArchive unless data['format'] == FORMAT && SUPPORTED_VERSIONS.include?(data['version'])
    raise InvalidArchive unless data['pages'].is_a?(Array) && data['media'].is_a?(Array)
    raise InvalidArchive unless data.fetch('series', []).is_a?(Array)
    raise InvalidArchive if data['pages'].size > Page.limit_for(@account)
    raise InvalidArchive if data.fetch('series', []).size > MAX_SERIES
    raise InvalidArchive if data['media'].size > MAX_ARCHIVE_ENTRIES - 1

    return unless data['version'] == VERSION

    series_ids = data.fetch('series', []).map { |series| series.fetch('id').to_s }
    page_ids = data['pages'].map { |page| page.fetch('backup_id').to_s }
    raise InvalidArchive unless series_ids.uniq.size == series_ids.size && page_ids.uniq.size == page_ids.size
  end

  def validate_archive!(zip)
    entries = zip.entries
    raise InvalidArchive if entries.size > MAX_ARCHIVE_ENTRIES
    raise InvalidArchive if entries.sum(&:size) > MAX_UNCOMPRESSED_SIZE

    manifest_entries = entries.select { |entry| entry.name == MANIFEST && !entry.directory? }
    raise InvalidArchive unless manifest_entries.one?

    manifest_entries.first
  end

  def validate_import_capacity!(page_count)
    ownership_remaining = [Page.limit_for(@account) - @account.pages.count, 0].max
    created_today = @account.pages.where(created_at: Time.current.all_day).count
    daily_remaining = [Page.daily_limit_for(@account) - created_today, 0].max
    raise InvalidArchive if page_count > [ownership_remaining, daily_remaining].min
  end

  def read_entry(entry, limit)
    raise InvalidArchive if entry.size > limit

    entry.get_input_stream do |input|
      data = input.read(limit + 1)
      raise InvalidArchive if data.bytesize > limit || input.read(1).present?

      data
    end
  end

  def import_media!(zip, media)
    total_size = 0

    media.each_with_object({}) do |attributes, result|
      path = attributes.fetch('path')
      entry = zip.find_entry(path)
      raise InvalidArchive if entry.nil? || !path.start_with?('page_media/') || entry.directory?
      raise InvalidArchive if entry.size > MAX_MEDIA_SIZE - total_size

      Tempfile.create(['page-media', File.extname(path)]) do |file|
        file.binmode
        total_size += copy_entry(entry, file, MAX_MEDIA_SIZE - total_size)
        file.rewind
        upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: File.basename(path), type: attributes['content_type'])
        attachment = @account.media_attachments.create!(file: upload, description: attributes['description'])
        result[attributes.fetch('id').to_s] = attachment.id.to_s
      end
    end
  end

  def copy_entry(entry, output, limit)
    copied = 0

    entry.get_input_stream do |input|
      loop do
        chunk = input.read(64.kilobytes)
        break if chunk.blank?

        copied += chunk.bytesize
        raise InvalidArchive if copied > limit

        output.write(chunk)
      end
    end

    copied
  end

  def import_series!(series)
    series.to_h do |attributes|
      imported = @account.page_series.create!(
        title: available_series_title(attributes.fetch('title')),
        description: attributes['description']
      )
      [attributes.fetch('id').to_s, imported.id]
    end
  end

  def import_page!(attributes, media_ids, series_ids)
    attributes = attributes.slice(*Page.attribute_names).except('id', 'account_id', 'created_at', 'updated_at', 'likes_count', 'draft')
    attributes['content'] = replace_media_ids(attributes['content'], media_ids)
    attributes['eye_catching_media_attachment_id'] = media_ids[attributes['eye_catching_media_attachment_id'].to_s]
    attributes['page_series_id'] = series_ids.fetch(attributes['page_series_id'].to_s) if attributes['page_series_id'].present?
    attributes['name'] = available_name(attributes.fetch('name'))
    @account.pages.create!(attributes)
  end

  def restore_series_mains!(series, series_ids, page_ids)
    series.each do |attributes|
      next if attributes['main_page_id'].blank?

      @account.page_series.find(series_ids.fetch(attributes.fetch('id').to_s)).update!(main_page_id: page_ids.fetch(attributes['main_page_id'].to_s))
    end
  end

  def replace_media_ids(blocks, media_ids)
    Array(blocks).map do |block|
      next block unless block.is_a?(Hash)

      block = block.deep_dup
      block['fileId'] = media_ids.fetch(block['fileId'].to_s) if block['type'] == 'image'
      block['children'] = replace_media_ids(block['children'], media_ids) if block['children'].is_a?(Array)
      block
    end
  end

  def available_name(name)
    return name unless @account.pages.exists?(name: name)

    base = name.first(Page::NAME_LENGTH_LIMIT - 10)
    sequence = 1
    sequence += 1 while @account.pages.exists?(name: "#{base}-#{sequence}")
    "#{base}-#{sequence}"
  end

  def available_series_title(title)
    return title unless @account.page_series.exists?(title: title)

    base = title.first(PageSeries::TITLE_LENGTH_LIMIT - 10)
    sequence = 1
    sequence += 1 while @account.page_series.exists?(title: "#{base} (#{sequence})")
    "#{base} (#{sequence})"
  end
end
