# frozen_string_literal: true

class Api::MisskeyCompat::Admin::DriveController < Api::MisskeyCompat::Admin::ServerBaseController
  ORIGINS = %w(combined local remote).freeze
  TYPE_PATTERN = %r{\A[a-zA-Z0-9/\-*]+\z}
  NO_SUCH_FILE_ID = 'caf3ca38-c6e5-472e-a30c-b05377dcc240'

  misskey_admin_endpoint :index, :show, kind: 'read:admin:drive', permission: :manage_users
  misskey_admin_endpoint :cleanup, :clean_remote_files, kind: 'write:admin:drive', permission: :manage_settings

  def index
    authorize :drive_file, :index?
    origin = params[:origin].nil? ? 'local' : params[:origin]
    return render_invalid_param('#/properties/origin', 'must be one of combined, local, remote') unless ORIGINS.include?(origin)
    return render_invalid_param('#/properties/type', 'must match pattern') unless params[:type].nil? || (params[:type].is_a?(String) && params[:type].match?(TYPE_PATTERN))

    limit = pagination_limit(default: 10, max: 100)
    files = file_scopes(origin).flat_map { |scope| paginate_admin_scope(filter_type(scope), default: limit, max: limit).to_a }
    files = files.sort_by(&:id)
    files = forward_pagination? ? files.first(limit) : files.reverse.first(limit)

    render json: files.map { |file| serialize_listed(file) }
  end

  def show
    file = find_file
    return render_error('No such file', 'NO_SUCH_FILE', 404, id: NO_SUCH_FILE_ID) if file.nil?

    render json: serialize_detail(file)
  end

  def cleanup
    MisskeyCompatOrphanedMediaCleanupWorker.perform_async
    head 204
  end

  def clean_remote_files
    MisskeyCompatRemoteMediaCleanupWorker.perform_async
    head 204
  end

  private

  def file_scopes(origin)
    return user_scopes(Account.find_by(id: params[:userId])) if params[:userId].present?
    return [remote_media_scope.where(accounts: { domain: TagManager.instance.normalize_domain(params[:hostname].to_s) })] if params[:hostname].present?

    scopes = []
    scopes.push(DriveFile.includes(:account, :custom_name, :folder), local_media_scope) unless origin == 'remote'
    scopes << remote_media_scope unless origin == 'local'
    scopes
  end

  def user_scopes(account)
    return [] if account.nil?
    return [remote_media_scope.where(account_id: account.id)] unless account.local?

    [DriveFile.includes(:account, :custom_name, :folder).where(account_id: account.id), local_media_scope.where(account_id: account.id)]
  end

  def local_media_scope
    MediaAttachment.local.where(drive_file_id: nil).joins(:account).merge(Account.local).includes(:account, :status)
  end

  def remote_media_scope
    MediaAttachment.remote.joins(:account).merge(Account.remote).includes(:account, :status)
  end

  def filter_type(scope)
    type = params[:type]
    return scope if type.blank?

    column = scope.klass.arel_table[:file_content_type]
    type.end_with?('/*') ? scope.where(column.matches("#{scope.klass.sanitize_sql_like(type.delete_suffix('*'))}%", nil, true)) : scope.where(column.eq(type))
  end

  def find_file
    if params[:fileId].present?
      DriveFile.find_by(id: params[:fileId]) || MediaAttachment.find_by(id: params[:fileId], drive_file_id: nil)
    elsif params[:url].is_a?(String) && params[:url].present?
      MediaAttachment.remote.find_by(remote_url: params[:url])
    end
  end

  def serialize_listed(file)
    data = MisskeyCompat::DriveFileSerializer.serialize(file)
    data[:folder] = file.is_a?(DriveFile) && file.folder ? MisskeyCompat::DriveFolderSerializer.serialize(file.folder, detail: true) : nil
    data[:user] = MisskeyCompat::UserSerializer.serialize(file.account)
    data
  end

  def serialize_detail(file)
    data = MisskeyCompat::DriveFileSerializer.serialize(file)
    remote = file.is_a?(MediaAttachment) && file.remote_url.present?

    {
      id: data[:id],
      userId: data[:userId],
      userHost: file.account&.domain,
      isLink: remote && file.file.blank?,
      maybePorn: false,
      maybeSensitive: false,
      isSensitive: data[:isSensitive],
      folderId: data[:folderId],
      src: remote ? file.remote_url : nil,
      uri: remote ? file.remote_url : nil,
      webpublicAccessKey: nil,
      thumbnailAccessKey: nil,
      accessKey: nil,
      webpublicType: nil,
      webpublicUrl: nil,
      thumbnailUrl: data[:thumbnailUrl],
      url: data[:url],
      storedInternal: !remote || file.file.present?,
      properties: data[:properties],
      blurhash: data[:blurhash],
      comment: data[:comment],
      size: data[:size],
      type: data[:type],
      name: data[:name],
      md5: data[:md5],
      createdAt: data[:createdAt],
      requestIp: nil,
      requestHeaders: nil,
    }
  end
end
