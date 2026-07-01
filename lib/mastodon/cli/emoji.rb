# frozen_string_literal: true

require 'rubygems/package'
require 'zip'
require_relative 'base'

module Mastodon::CLI
  class Emoji < Base
    IMAGE_EXTENSIONS = %w(.png .gif .webp .jpg .jpeg).freeze
    MANIFEST_NAMES   = %w(metadata.json meta.json).freeze

    option :prefix
    option :suffix
    option :overwrite, type: :boolean
    option :unlisted, type: :boolean
    option :category
    desc 'import PATH', 'Import emoji from a TAR GZIP or ZIP archive at PATH'
    long_desc <<-LONG_DESC
      Imports custom emoji from an archive specified by PATH. Both TAR
      GZIP ('.tar.gz') and ZIP ('.zip') archives are supported; the
      format is detected automatically.

      If the archive contains a 'metadata.json' manifest (as produced
      by the export command), category, license, aliases and picker
      visibility are restored as well. Existing emoji are updated when
      the manifest entry is more recently modified than the local copy;
      older entries are ignored. The --overwrite option forces every
      emoji (image included) to be overwritten regardless of timestamps.

      Misskey emoji bundles (ZIP archives containing a 'meta.json'
      manifest) are recognized as well: their emoji name, category,
      license and aliases are imported.

      Existing emoji will be skipped unless the --overwrite option
      is provided, in which case they will be overwritten.

      You can specify a --category under which the emojis will be
      grouped together.

      With the --prefix option, a prefix can be added to all
      generated shortcodes. Likewise, the --suffix option controls
      the suffix of all shortcodes.

      With the --unlisted option, the processed emoji will not be
      visible in the emoji picker (but still usable via other means)
    LONG_DESC
    def import(path)
      category = options[:category] ? CustomEmojiCategory.find_or_create_by(name: options[:category]) : nil
      manifest = read_manifest(path)

      results = if zip_archive?(path)
                  import_from_zip(path, manifest, category)
                else
                  import_from_targz(path, manifest, category)
                end

      imported = results.count(:imported)
      updated  = results.count(:updated)
      skipped  = results.count(:skipped)
      failed   = results.count(:failed)

      say("Imported #{imported}, updated #{updated}, skipped #{skipped}, failed to import #{failed}", color(imported + updated, skipped, failed))
    end

    option :category
    option :overwrite, type: :boolean
    desc 'export PATH', 'Export emoji to a TAR GZIP archive at PATH'
    long_desc <<-LONG_DESC
      Exports custom emoji to 'export.tar.gz' at PATH.

      A 'metadata.json' manifest is written alongside the images,
      recording each emoji's category, license, aliases, picker
      visibility and modification timestamps so they can be restored
      on import.

      The --category option dumps only the specified category.
      If this option is not specified, all emoji will be exported.

      The --overwrite option will overwrite an existing archive.
    LONG_DESC
    def export(path)
      exported         = 0
      skipped          = 0
      category         = CustomEmojiCategory.find_by(name: options[:category])
      export_file_name = File.join(path, 'export.tar.gz')

      fail_with_message "Archive already exists! Use '--overwrite' to overwrite it!" if File.file?(export_file_name) && !options[:overwrite]
      fail_with_message "Unable to find category '#{options[:category]}'!" if category.nil? && options[:category]

      manifest = { 'version' => 1, 'emojis' => {} }

      File.open(export_file_name, 'wb') do |file|
        Zlib::GzipWriter.wrap(file) do |gzip|
          Gem::Package::TarWriter.new(gzip) do |tar|
            scope = !options[:category] || category.nil? ? CustomEmoji.local : category.emojis
            scope.includes(:category).find_each do |emoji|
              unless emoji.image.exists?
                say("Skipping '#{emoji.shortcode}' (missing image file)...", :yellow)
                skipped += 1
                next
              end

              filename = emoji.shortcode + File.extname(emoji.image_file_name)
              say("Adding '#{emoji.shortcode}'...")
              tar.add_file_simple(filename, 0o644, emoji.image_file_size) do |io|
                io.write Paperclip.io_adapters.for(emoji.image).read
                exported += 1
              end
              manifest['emojis'][filename] = {
                'shortcode' => emoji.shortcode,
                'category' => emoji.category&.name,
                'license' => emoji.license,
                'aliases' => emoji.aliases,
                'visible_in_picker' => emoji.visible_in_picker,
                'updated_at' => emoji.updated_at&.iso8601,
                'image_updated_at' => emoji.image_updated_at&.iso8601,
              }
            end

            json = JSON.generate(manifest)
            tar.add_file_simple('metadata.json', 0o644, json.bytesize) do |io|
              io.write(json)
            end
          end
        end
      end
      say("Exported #{exported}, skipped #{skipped}", skipped.zero? ? :green : :yellow)
    end

    option :remote_only, type: :boolean
    option :suspended_only, type: :boolean
    desc 'purge', 'Remove all custom emoji'
    long_desc <<-LONG_DESC
      Removes all custom emoji.

      With the --remote-only option, only remote emoji will be deleted.

      With the --suspended-only option, only emoji from suspended servers will be deleted.
    LONG_DESC
    def purge
      if options[:suspended_only]
        DomainBlock.where(severity: :suspend).find_each do |domain_block|
          CustomEmoji.by_domain_and_subdomains(domain_block.domain).find_in_batches do |custom_emojis|
            AttachmentBatch.new(CustomEmoji, custom_emojis).delete
          end
        end
      else
        scope = options[:remote_only] ? CustomEmoji.remote : CustomEmoji
        scope.in_batches.destroy_all
      end

      say('OK', :green)
    end

    private

    def zip_archive?(path)
      File.open(path, 'rb') { |file| file.read(2) } == 'PK'
    end

    def import_from_targz(path, manifest, category)
      results = []

      Gem::Package::TarReader.new(Zlib::GzipReader.open(path)) do |tar|
        tar.each do |entry|
          next unless entry.file? && importable_image?(entry.full_name)

          results << import_entry(entry.full_name, manifest, category) { entry.read }
        end
      end

      results
    end

    def import_from_zip(path, manifest, category)
      results = []

      Zip::File.open(path) do |zip|
        zip.each do |entry|
          next unless entry.file? && importable_image?(entry.name)

          results << import_entry(entry.name, manifest, category) { entry.get_input_stream.read }
        end
      end

      results
    end

    def importable_image?(full_name)
      filename = File.basename(full_name)

      # Skip macOS shadow files
      return false if filename.start_with?('._')

      IMAGE_EXTENSIONS.include?(File.extname(filename).downcase)
    end

    def import_entry(full_name, manifest, category)
      filename     = File.basename(full_name)
      meta         = manifest.dig('emojis', filename) || manifest.dig('emojis', full_name) || {}
      base         = meta['shortcode'].presence || File.basename(filename, '.*')
      shortcode    = [options[:prefix], base, options[:suffix]].compact.join
      custom_emoji = CustomEmoji.local.find_by('LOWER(shortcode) = ?', shortcode.downcase)
      new_record   = custom_emoji.nil?
      archive_time = parse_time(meta['updated_at'])

      unless new_record
        skip =
          if archive_time.nil?
            !options[:overwrite]
          else
            !options[:overwrite] && custom_emoji.updated_at.present? && custom_emoji.updated_at >= archive_time
          end

        return :skipped if skip
      end

      custom_emoji ||= CustomEmoji.new(shortcode: shortcode, domain: nil)

      if new_record || options[:overwrite]
        custom_emoji.image = StringIO.new(yield)
        custom_emoji.image_file_name = filename
      end

      apply_metadata(custom_emoji, meta, category)

      return :skipped if !new_record && !options[:overwrite] && !custom_emoji.changed?

      if custom_emoji.save
        new_record ? :imported : :updated
      else
        say('Failure/Error: ', :red)
        say(full_name)
        shell.indent(2) do
          say(custom_emoji.errors[:image].join(', '), :red)
        end
        :failed
      end
    end

    def read_manifest(path)
      raw = zip_archive?(path) ? read_zip_manifest(path) : read_targz_manifest(path)
      normalize_manifest(raw)
    end

    def read_targz_manifest(path)
      Gem::Package::TarReader.new(Zlib::GzipReader.open(path)) do |tar|
        tar.each do |entry|
          next unless entry.file? && MANIFEST_NAMES.include?(File.basename(entry.full_name))

          return parse_json(entry.read)
        end
      end

      nil
    end

    def read_zip_manifest(path)
      Zip::File.open(path) do |zip|
        entry = zip.find { |candidate| candidate.file? && MANIFEST_NAMES.include?(File.basename(candidate.name)) }

        return parse_json(entry.get_input_stream.read) if entry
      end

      nil
    end

    def parse_json(data)
      JSON.parse(data)
    rescue JSON::ParserError
      nil
    end

    # Normalizes both Mastodon manifests (where 'emojis' is a hash keyed
    # by filename) and Misskey bundles (where 'emojis' is an array of
    # records) into a single filename-keyed hash of metadata.
    def normalize_manifest(raw)
      return {} unless raw.is_a?(Hash)

      emojis = raw['emojis']

      if emojis.is_a?(Array)
        normalized = {}

        emojis.each do |record|
          next unless record.is_a?(Hash)

          filename = record['fileName']
          next if filename.blank?

          info = record['emoji'].is_a?(Hash) ? record['emoji'] : {}

          normalized[filename] = {
            'shortcode' => info['name'],
            'category' => info['category'],
            'license' => info['license'],
            'aliases' => info['aliases'],
          }
        end

        { 'emojis' => normalized }
      elsif emojis.is_a?(Hash)
        raw
      else
        {}
      end
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end

    def apply_metadata(emoji, meta, category_option)
      if category_option
        emoji.category = category_option
      elsif meta.key?('category')
        emoji.category = meta['category'].present? ? CustomEmojiCategory.find_or_create_by(name: meta['category']) : nil
      end

      emoji.license = meta['license'] if meta.key?('license')
      emoji.aliases = meta['aliases'] if meta['aliases'].is_a?(Array)

      if options[:unlisted]
        emoji.visible_in_picker = false
      elsif meta.key?('visible_in_picker')
        emoji.visible_in_picker = meta['visible_in_picker']
      elsif emoji.new_record?
        emoji.visible_in_picker = true
      end
    end

    def color(green, _yellow, red)
      if !green.zero? && red.zero?
        :green
      elsif red.zero?
        :yellow
      else
        :red
      end
    end
  end
end
