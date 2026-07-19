# frozen_string_literal: true

class CreateDriveFileService < BaseService
  include Redisable

  class NoFreeSpaceError < StandardError; end
  class NoSuchFolderError < StandardError; end

  def call(account:, user:, file:, thumbnail: nil, name: nil, folder_id: nil, folder_id_provided: false, description: nil, sensitive: nil)
    @account = account
    @user = user
    @upload = file
    @name = name
    @folder_id = resolve_folder_id(folder_id, folder_id_provided)
    @attributes = { file: file, thumbnail: thumbnail, description: description, folder_id: @folder_id, sensitive: sensitive }.compact
    @sha256 = Digest::SHA256.file(uploaded_path).hexdigest
    @md5 = Digest::MD5.file(uploaded_path).hexdigest

    drive_file = account.with_lock do
      existing = account.drive_files.find_by(sha256: @sha256)
      if existing
        @created = false
        next update_existing_file(existing)
      end

      @created = true
      create_file
    end

    broadcast(drive_file)
    drive_file
  rescue ActiveRecord::RecordNotUnique
    @created = false
    update_existing_file(account.drive_files.find_by!(sha256: @sha256)).tap { |file| broadcast(file) }
  end

  private

  def broadcast(drive_file)
    return if drive_file.nil?

    MisskeyCompat::Streaming.broadcast_drive_file(redis, @account, drive_file, @created ? 'fileCreated' : 'fileUpdated')
  end

  def create_file
    candidate = @account.drive_files.build(@attributes.except(:file, :thumbnail).merge(sha256: @sha256, md5: @md5))
    candidate.file = @attributes[:file]
    candidate.thumbnail = @attributes[:thumbnail] if @attributes.key?(:thumbnail)
    candidate.display_name = uploaded_name
    raise ActiveRecord::RecordInvalid, candidate unless candidate.valid?
    raise NoFreeSpaceError unless within_quota?(candidate.quota_storage_file_size)

    candidate.tap(&:save!)
  end

  def update_existing_file(file)
    file.display_name = uploaded_name if file.custom_name.nil?
    file.update!(@attributes.except(:file, :thumbnail).compact_blank)
    file
  end

  def resolve_folder_id(folder_id, folder_id_provided)
    selected_id = folder_id_provided ? folder_id.presence : @user.settings[:drive_default_folder_id].presence
    return if selected_id.blank?
    return selected_id if @account.drive_folders.exists?(id: selected_id)
    return unless folder_id_provided

    raise NoSuchFolderError
  end

  def uploaded_name
    return unless @user.settings[:drive_keep_original_filename]

    @name.presence || @upload.original_filename
  end

  def uploaded_path
    @upload.respond_to?(:path) ? @upload.path : @upload.tempfile.path
  end

  def within_quota?(incoming_size)
    quota = @account.drive_quota_bytes
    return true if quota <= 0

    @account.drive_files.sum(:storage_file_size).to_i + incoming_size.to_i <= quota
  end
end
