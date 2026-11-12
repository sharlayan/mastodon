# frozen_string_literal: true

require 'zip'

class MisskeyCompatEmojiImportWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: false

  MAX_ENTRIES = 5_000
  MAX_META_SIZE = 10.megabytes
  FILE_NAME_PATTERN = /\A[a-zA-Z0-9_]+?([a-zA-Z0-9.]+)?\z/
  NAME_PATTERN = /\A[a-zA-Z0-9_]+\z/

  def perform(drive_file_id, account_id)
    drive_file = DriveFile.find_by(id: drive_file_id)
    @account = Account.find_by(id: account_id)
    return if drive_file.nil? || @account.nil?

    adapter = Paperclip.io_adapters.for(drive_file.file)
    Zip::File.open(adapter.path) { |zip| import(zip) }
  rescue Zip::Error, JSON::ParserError => e
    Rails.logger.warn("Misskey-compat emoji import #{drive_file_id} failed: #{e.message}")
  end

  private

  def import(zip)
    meta_entry = zip.find_entry('meta.json')
    return if meta_entry.nil? || meta_entry.size > MAX_META_SIZE

    records = JSON.parse(meta_entry.get_input_stream.read)['emojis']
    return unless records.is_a?(Array)

    imported = records.first(MAX_ENTRIES).count { |record| import_record(zip, record) }
    purge_emoji_cache if imported.positive?
  end

  def import_record(zip, record)
    return false unless record.is_a?(Hash) && record['downloaded'] && record['emoji'].is_a?(Hash)

    file_name = record['fileName'].to_s
    info = record['emoji']
    name = info['name'].to_s
    return false unless file_name.match?(FILE_NAME_PATTERN) && name.match?(NAME_PATTERN)

    entry = zip.find_entry(file_name)
    return false if entry.nil? || entry.size > CustomEmoji::LOCAL_LIMIT

    save_emoji(name, file_name, entry.get_input_stream.read(CustomEmoji::LOCAL_LIMIT), info)
  end

  def save_emoji(name, file_name, data, info)
    emoji = CustomEmoji.local.find_or_initialize_by(shortcode: name)
    action = emoji.new_record? ? :create : :update
    emoji.image = StringIO.new(data)
    emoji.image_file_name = file_name
    emoji.assign_attributes(
      category_id: info['category'].present? ? CustomEmojiCategory.find_or_create_by!(name: info['category'].to_s).id : nil,
      aliases: Array(info['aliases']).map(&:to_s).compact_blank.uniq,
      license: info['license'].presence&.to_s,
      is_sensitive: info['isSensitive'] == true,
      local_only: info['localOnly'] == true
    )
    return false unless emoji.save

    @account.action_logs.create(action: action, target: emoji)
    true
  rescue ActiveRecord::RecordInvalid, Paperclip::Error => e
    Rails.logger.warn("Misskey-compat emoji import skipped #{name}: #{e.message}")
    false
  end

  def purge_emoji_cache
    Rails.cache.delete('api/v1/custom_emojis/index')
    Rails.cache.delete_matched('emoji:*')
  end
end
