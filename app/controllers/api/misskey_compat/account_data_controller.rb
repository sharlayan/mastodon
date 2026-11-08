# frozen_string_literal: true

class Api::MisskeyCompat::AccountDataController < Api::MisskeyCompat::BaseController
  include Redisable
  include Lockable

  EXPORT_ACTIONS = %i(export_following export_blocking export_mute export_user_lists export_clips export_notes).freeze
  IMPORT_ACTIONS = %i(import_following import_blocking import_muting import_user_lists).freeze

  EXPORTS = {
    following: { filename: 'following_accounts', extension: 'csv', content_type: 'text/csv', method: :to_following_accounts_csv, header_lines: 1 },
    blocking: { filename: 'blocked_accounts', extension: 'csv', content_type: 'text/csv', method: :to_blocked_accounts_csv, header_lines: 0 },
    muting: { filename: 'muted_accounts', extension: 'csv', content_type: 'text/csv', method: :to_muted_accounts_csv, header_lines: 1 },
    lists: { filename: 'lists', extension: 'csv', content_type: 'text/csv', method: :to_lists_csv, header_lines: 0 },
    clips: { filename: 'clips', extension: 'json', content_type: 'application/json', method: :to_clips_json },
  }.freeze

  IMPORT_ERROR_IDS = {
    following: {
      no_such_file: 'b98644cf-a5ac-4277-a502-0b8054a709a3',
      unexpected_file_type: '660f3599-bce0-4f95-9dde-311fd841c183',
      too_big_file: 'dee9d4ed-ad07-43ed-8b34-b2856398bc60',
      empty_file: '31a1b42c-06f7-42ae-8a38-a661c5c9f691',
    },
    blocking: {
      no_such_file: 'ebb53e5f-6574-9c0c-0b92-7ca6def56d7e',
      unexpected_file_type: 'b6fab7d6-d945-d67c-dfdb-32da1cd12cfe',
      too_big_file: 'b7fbf0b1-aeef-3b21-29ef-fadd4cb72ccf',
      empty_file: '6f3a4dcc-f060-a707-4950-806fbdbe60d6',
    },
    muting: {
      no_such_file: 'e674141e-bd2a-ba85-e616-aefb187c9c2a',
      unexpected_file_type: '568c6e42-c86c-ba09-c004-517f83f9f1a8',
      too_big_file: '9b4ada6d-d7f7-0472-0713-4f558bd1ec9c',
      empty_file: 'd2f12af1-e7b4-feac-86a3-519548f2728e',
    },
    lists: {
      no_such_file: 'ea9cc34f-c415-4bc6-a6fe-28ac40357049',
      unexpected_file_type: 'a3c9edda-dd9b-4596-be6a-150ef813745c',
      too_big_file: 'ae6e7a22-971b-4b52-b2be-fc0b9b121fe9',
      empty_file: '99efe367-ce6e-4d44-93f8-5fae7b040356',
    },
  }.freeze

  requires_write_scope(*EXPORT_ACTIONS, *IMPORT_ACTIONS)
  requires_misskey_permission 'write:account', *EXPORT_ACTIONS, *IMPORT_ACTIONS

  before_action :require_user!
  before_action :require_native_user_token!
  before_action :require_drive_enabled!, except: :export_notes
  before_action :require_clips_enabled!, only: :export_clips
  before_action :enforce_account_data_rate_limit!

  rescue_from Mastodon::NotPermittedError, Mastodon::RaceConditionError do
    render_error(I18n.t('errors.429'), 'RATE_LIMIT_EXCEEDED', 429, id: '22d05606-fbcf-421a-a2db-b32610dcfd1b')
  end

  def export_following
    export_to_drive(:following)
  end

  def export_blocking
    export_to_drive(:blocking)
  end

  def export_mute
    export_to_drive(:muting)
  end

  def export_user_lists
    export_to_drive(:lists)
  end

  def export_clips
    export_to_drive(:clips)
  end

  def export_notes
    backup = nil

    with_redis_lock("backup:#{current_user.id}") do
      authorize :backup, :create?
      backup = current_user.backups.create!
    end

    BackupWorker.perform_async(backup.id)
    head 204
  end

  def import_following
    import_from_drive(:following)
  end

  def import_blocking
    import_from_drive(:blocking)
  end

  def import_muting
    import_from_drive(:muting)
  end

  def import_user_lists
    import_from_drive(:lists)
  end

  private

  def require_clips_enabled!
    render_error('Clips are not available on this server', 'UNAVAILABLE', 400) unless Setting.clips_enabled
  end

  def enforce_account_data_rate_limit!
    rate_limited?(:misskey_compat_account_data)
  end

  def export_to_drive(kind)
    definition = EXPORTS.fetch(kind)
    data = Export.new(current_account).public_send(definition[:method])
    return render_error('Nothing to export', 'NOTHING_TO_EXPORT', 400) if export_empty?(definition, data)

    filename = "#{definition[:filename]}-#{Time.now.utc.strftime('%Y-%m-%d-%H-%M-%S')}.#{definition[:extension]}"

    Tempfile.create([definition[:filename], ".#{definition[:extension]}"]) do |tempfile|
      tempfile.binmode
      tempfile.write(data)
      tempfile.rewind

      upload = ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: definition[:content_type])
      CreateDriveFileService.new.call(account: current_account, user: current_user, file: upload, generated_export: true)
    end

    head 204
  rescue CreateDriveFileService::NoFreeSpaceError
    render_error('Drive storage quota exceeded', 'NO_FREE_SPACE', 422)
  rescue ActiveRecord::RecordInvalid
    render_error('The exported file could not be stored in the drive', 'INVALID_FILE', 422)
  end

  def export_empty?(definition, data)
    return JSON.parse(data).values.all?(&:empty?) if definition[:extension] == 'json'

    data.lines.size <= definition[:header_lines]
  end

  def import_from_drive(type)
    drive_file = current_account.drive_files.find_by(id: params[:fileId])
    return import_error(type, :no_such_file, 'No such file', 'NO_SUCH_FILE') if drive_file.nil?

    size = drive_file.file_file_size.to_i
    return import_error(type, :empty_file, 'That file is empty', 'EMPTY_FILE') if size.zero?
    return import_error(type, :too_big_file, 'That file is too big', 'TOO_BIG_FILE') if size > Form::Import::FILE_SIZE_LIMIT

    tempfile = fetch_drive_file(drive_file)
    return import_error(type, :no_such_file, 'No such file', 'NO_SUCH_FILE') if tempfile.nil?

    upload = ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: drive_file.display_name.presence || 'import.csv', type: 'text/csv')
    import = Form::Import.new(current_account: current_account, type: type, mode: :merge, data: upload)
    return import_error(type, :unexpected_file_type, import.errors.full_messages.to_sentence, 'UNEXPECTED_FILE_TYPE') unless import.save

    import.bulk_import.update!(state: :scheduled)
    BulkImportWorker.perform_async(import.bulk_import.id)
    head 204
  ensure
    tempfile&.close!
  end

  def fetch_drive_file(drive_file)
    tempfile = Tempfile.new(['misskey-import', '.csv'])
    copied = drive_file.file.copy_to_local_file(:original, tempfile.path)

    if copied == false || File.empty?(tempfile.path)
      tempfile.close!
      return
    end

    tempfile.open.binmode
    tempfile
  rescue Errno::ENOENT
    tempfile.close!
    nil
  end

  def import_error(type, error, message, code)
    render_error(message, code, 400, id: IMPORT_ERROR_IDS.dig(type, error))
  end
end
