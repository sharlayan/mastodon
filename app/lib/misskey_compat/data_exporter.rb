# frozen_string_literal: true

class MisskeyCompat::DataExporter
  include RoutingHelper

  FAVORITES_BATCH_SIZE = 100
  EMOJI_NAME_FORMAT = /\A[a-zA-Z0-9_]+\z/

  ENTITIES = {
    'antenna' => { filename: 'antennas', extension: 'json', content_type: 'application/json' },
    'favorite' => { filename: 'favorites', extension: 'json', content_type: 'application/json' },
    'customEmoji' => { filename: 'custom-emojis', extension: 'zip', content_type: 'application/zip' },
  }.freeze

  def initialize(user)
    @user = user
    @account = user.account
  end

  def call(entity)
    definition = ENTITIES.fetch(entity)
    filename = "#{definition[:filename]}-#{Time.now.utc.strftime('%Y-%m-%d-%H-%M-%S')}.#{definition[:extension]}"

    Tempfile.create([definition[:filename], ".#{definition[:extension]}"]) do |tempfile|
      tempfile.binmode
      write(entity, tempfile)
      tempfile.flush
      tempfile.rewind

      upload = ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: definition[:content_type])
      CreateDriveFileService.new.call(account: @account, user: @user, file: upload, generated_export: true)
    end
  end

  private

  def write(entity, io)
    case entity
    when 'antenna'
      io.write(MisskeyCompat::AntennaPorter.new(@account).export_json)
    when 'favorite'
      write_favorites(io)
    when 'customEmoji'
      write_custom_emojis(io)
    end
  end

  def write_favorites(io)
    io.write('[')
    first = true
    @account.favourites.includes(status: [:account, :media_attachments, :preloadable_poll]).find_in_batches(batch_size: FAVORITES_BATCH_SIZE) do |favourites|
      statuses = favourites.filter_map(&:status)
      context = MisskeyCompat::SerializationContext.for(statuses, current_account: @account)
      favourites.each do |favourite|
        next if favourite.status.nil? || !context.visible?(favourite.status)

        io.write(',') unless first
        io.write(JSON.generate(favorite_entry(favourite, context)))
        first = false
      end
    end
    io.write(']')
  end

  def favorite_entry(favourite, context)
    status = favourite.status
    note = MisskeyCompat::NoteSerializer.serialize(status, embed_relations: false, context: context)
    account = status.account

    {
      id: MisskeyCompat::MiId.encode(favourite.id),
      createdAt: favourite.created_at.utc.iso8601(3),
      note: note.slice(:id, :text, :createdAt, :fileIds, :replyId, :renoteId).merge(
        poll: poll_entry(status),
        cw: note[:cw],
        visibility: note[:visibility],
        visibleUserIds: note[:visibleUserIds],
        localOnly: note[:localOnly],
        reactionAcceptance: note[:reactionAcceptance],
        uri: note[:uri],
        url: note[:url],
        user: { id: MisskeyCompat::MiId.encode(account.id), name: account.display_name.presence, username: account.username, host: account.domain, uri: account.local? ? nil : account.uri }
      ),
    }
  end

  def poll_entry(status)
    poll = status.preloadable_poll
    return if poll.nil?

    {
      noteId: MisskeyCompat::MiId.encode(status.id),
      expiresAt: poll.expires_at&.utc&.iso8601(3),
      multiple: poll.multiple,
      choices: poll.options,
      votes: poll.cached_tallies,
      noteVisibility: MisskeyCompat::NoteSerializer::VISIBILITY_MAP.fetch(status.visibility, 'public'),
      userId: MisskeyCompat::MiId.encode(status.account_id),
      userHost: status.account.domain,
    }
  end

  def write_custom_emojis(io)
    Dir.mktmpdir('misskey-emoji-export') do |dir|
      entries = CustomEmoji.local.enabled.includes(:category).order(:id).filter_map { |emoji| export_emoji(emoji, dir) }
      meta = { metaVersion: 2, host: Rails.configuration.x.local_domain, exportedAt: Time.now.utc.strftime('%a %b %d %Y %H:%M:%S GMT+0000 (Coordinated Universal Time)'), emojis: entries }

      Zip::OutputStream.write_buffer(io) do |zip|
        zip.put_next_entry('meta.json')
        zip.write(JSON.generate(meta))
        entries.select { |entry| entry[:downloaded] }.each do |entry|
          zip.put_next_entry(entry[:fileName])
          zip.write(File.binread(File.join(dir, entry[:fileName])))
        end
      end
    end
  end

  def export_emoji(emoji, dir)
    return unless emoji.shortcode.match?(EMOJI_NAME_FORMAT)

    extension = MIME::Types[emoji.image_content_type.presence || 'image/png'].first&.preferred_extension
    file_name = extension ? "#{emoji.shortcode}.#{extension}" : emoji.shortcode
    { fileName: file_name, downloaded: copy_emoji(emoji, File.join(dir, file_name)), emoji: emoji_entry(emoji) }
  end

  def copy_emoji(emoji, path)
    emoji.image.copy_to_local_file(:original, path)
    File.size?(path).present?
  rescue Errno::ENOENT, Paperclip::Errors::NotIdentifiedByImageMagickError
    false
  end

  def emoji_entry(emoji)
    url = full_asset_url(emoji.image.url(:original))

    {
      id: MisskeyCompat::MiId.encode(emoji.id),
      updatedAt: emoji.updated_at&.utc&.iso8601(3),
      name: emoji.shortcode,
      host: nil,
      category: emoji.category&.name,
      originalUrl: url,
      publicUrl: url,
      uri: nil,
      type: emoji.image_content_type,
      aliases: emoji.aliases,
      license: emoji.license,
      localOnly: emoji.local_only,
      isSensitive: emoji.is_sensitive,
      roleIdsThatCanBeUsedThisEmojiAsReaction: [],
      roleIdsThatCanNotBeUsedThisEmojiAsReaction: [],
    }
  end
end
