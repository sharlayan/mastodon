# frozen_string_literal: true

require 'zip'

module Sharlayan
  module CLI
    module EmojiArchive
      IMAGE_EXTENSIONS = %w(.png .gif .webp .jpg .jpeg).freeze
      MANIFEST_NAMES = %w(metadata.json meta.json).freeze

      def import(path)
        category = options[:category] ? CustomEmojiCategory.find_or_create_by(name: options[:category]) : nil
        manifest = read_manifest(path)
        results = zip_archive?(path) ? import_from_zip(path, manifest, category) : import_from_targz(path, manifest, category)

        imported = results.count(:imported)
        updated = results.count(:updated)
        skipped = results.count(:skipped)
        failed = results.count(:failed)

        say("Imported #{imported}, updated #{updated}, skipped #{skipped}, failed to import #{failed}", color(imported + updated, skipped, failed))
      end

      def export(path)
        exported = 0
        skipped = 0
        category = CustomEmojiCategory.find_by(name: options[:category])
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
                manifest['emojis'][filename] = manifest_metadata(emoji)
              end

              add_manifest(tar, manifest)
            end
          end
        end
        say("Exported #{exported}, skipped #{skipped}", skipped.zero? ? :green : :yellow)
      end

      private

      def manifest_metadata(emoji)
        {
          'shortcode' => emoji.shortcode,
          'category' => emoji.category&.name,
          'license' => emoji.license,
          'aliases' => emoji.aliases,
          'visible_in_picker' => emoji.visible_in_picker,
          'is_sensitive' => emoji.is_sensitive,
          'local_only' => emoji.local_only,
          'updated_at' => emoji.updated_at&.iso8601,
          'image_updated_at' => emoji.image_updated_at&.iso8601,
        }
      end

      def add_manifest(tar, manifest)
        json = JSON.generate(manifest)
        tar.add_file_simple('metadata.json', 0o644, json.bytesize) { |io| io.write(json) }
      end

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
        return false if filename.start_with?('._')

        IMAGE_EXTENSIONS.include?(File.extname(filename).downcase)
      end

      def import_entry(full_name, manifest, category)
        filename = File.basename(full_name)
        meta = manifest.dig('emojis', filename) || manifest.dig('emojis', full_name) || {}
        base = meta['shortcode'].presence || File.basename(filename, '.*')
        shortcode = [options[:prefix], base, options[:suffix]].compact.join
        custom_emoji = CustomEmoji.local.find_by('LOWER(shortcode) = ?', shortcode.downcase)
        new_record = custom_emoji.nil?
        archive_time = parse_time(meta['updated_at'])

        return :skipped if skip_existing?(custom_emoji, archive_time)

        custom_emoji ||= CustomEmoji.new(shortcode:, domain: nil)

        if new_record || options[:overwrite]
          custom_emoji.image = StringIO.new(yield)
          custom_emoji.image_file_name = filename
        end

        apply_metadata(custom_emoji, meta, category)
        return :skipped if !new_record && !options[:overwrite] && !custom_emoji.changed?

        save_entry(custom_emoji, new_record, full_name)
      end

      def skip_existing?(custom_emoji, archive_time)
        return false unless custom_emoji
        return !options[:overwrite] if archive_time.nil?

        !options[:overwrite] && custom_emoji.updated_at.present? && custom_emoji.updated_at >= archive_time
      end

      def save_entry(custom_emoji, new_record, full_name)
        return new_record ? :imported : :updated if custom_emoji.save

        say('Failure/Error: ', :red)
        say(full_name)
        shell.indent(2) { say(custom_emoji.errors[:image].join(', '), :red) }
        :failed
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

      def normalize_manifest(raw)
        return {} unless raw.is_a?(Hash)

        emojis = raw['emojis']
        return raw if emojis.is_a?(Hash)
        return {} unless emojis.is_a?(Array)

        { 'emojis' => emojis.each_with_object({}) { |record, normalized| normalize_misskey_record(record, normalized) } }
      end

      def normalize_misskey_record(record, normalized)
        return unless record.is_a?(Hash)

        filename = record['fileName']
        return if filename.blank?

        info = record['emoji'].is_a?(Hash) ? record['emoji'] : {}
        normalized[filename] = {
          'shortcode' => info['name'],
          'category' => info['category'],
          'license' => info['license'],
          'aliases' => info['aliases'],
          'is_sensitive' => info['isSensitive'],
          'local_only' => info['localOnly'],
        }
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
        emoji.is_sensitive = meta['is_sensitive'] if meta.key?('is_sensitive')
        emoji.local_only = meta['local_only'] if meta.key?('local_only')

        if options[:unlisted]
          emoji.visible_in_picker = false
        elsif meta.key?('visible_in_picker')
          emoji.visible_in_picker = meta['visible_in_picker']
        elsif emoji.new_record?
          emoji.visible_in_picker = true
        end
      end
    end
  end
end
