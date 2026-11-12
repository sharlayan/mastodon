# frozen_string_literal: true

class Api::MisskeyCompat::Admin::EmojiController < Api::MisskeyCompat::Admin::ServerBaseController
  NAME_PATTERN = /\A[a-zA-Z0-9_]+\z/
  NO_SUCH_FILE_IDS = { 'create' => 'fc46b5a4-6b92-4c33-ac66-b806659bb5cf', 'update' => '14fb9fd9-0731-4e2f-aeb9-f09e4740333d' }.freeze
  NO_SUCH_EMOJI_IDS = { 'update' => '684dec9d-a8c2-4364-9aa8-456c49cb1dc8', 'destroy' => 'be83669b-773a-44b7-b1f8-e5e5170ac3c2', 'copy' => 'e2785b66-dca3-4087-9cac-b93c541cc425' }.freeze
  DUPLICATE_NAME_ID = 'f7a3462c-4e6e-4069-8421-b9bd4f4c3975'
  HOST_TYPES = %w(local remote all).freeze
  SORT_COLUMNS = {
    'id' => 'custom_emojis.id',
    'updatedAt' => 'custom_emojis.updated_at',
    'name' => 'custom_emojis.shortcode',
    'host' => 'custom_emojis.domain',
    'uri' => 'custom_emojis.uri',
    'publicUrl' => 'custom_emojis.image_remote_url',
    'type' => 'custom_emojis.image_content_type',
    'aliases' => 'custom_emojis.aliases',
    'category' => 'custom_emoji_categories.name',
    'license' => 'custom_emojis.license',
    'isSensitive' => 'custom_emojis.is_sensitive',
    'localOnly' => 'custom_emojis.local_only',
    'roleIdsThatCanBeUsedThisEmojiAsReaction' => 'custom_emojis.id',
  }.freeze

  misskey_admin_endpoint :index, :remote, :search, kind: 'read:admin:emoji', role: :policy, permission: :manage_custom_emojis
  misskey_admin_endpoint :create, :update, :destroy, :destroy_bulk, :copy, :add_aliases, :remove_aliases, :set_aliases, :set_category, :set_license,
                         kind: 'write:admin:emoji', role: :policy, permission: :manage_custom_emojis
  misskey_admin_endpoint :import_zip, kind: nil, role: :policy, permission: :manage_custom_emojis, secure: true

  def index
    scope = CustomEmoji.local.includes(:category)
    scope = filter_local_query(scope, params[:query]) if params[:query].present?
    render json: paginate_admin_scope(scope).map { |emoji| MisskeyCompat::EmojiSerializer.detailed(emoji) }
  end

  def remote
    scope = params[:host].present? ? CustomEmoji.where(domain: TagManager.instance.normalize_domain(params[:host].to_s)) : CustomEmoji.remote
    scope = scope.where('custom_emojis.shortcode LIKE ?', "%#{CustomEmoji.sanitize_sql_like(params[:query].to_s)}%") if params[:query].present?
    render json: paginate_admin_scope(scope.includes(:category)).map { |emoji| MisskeyCompat::EmojiSerializer.detailed(emoji) }
  end

  def search
    query = params[:query].is_a?(ActionController::Parameters) ? params[:query] : ActionController::Parameters.new({})
    return render_invalid_param('#/properties/query/properties/hostType', 'must be one of local, remote, all') if query.key?(:hostType) && HOST_TYPES.exclude?(query[:hostType])
    return render_invalid_param('#/properties/sortKeys', 'must be array of supported sort keys') unless valid_sort_keys?

    scope = filter_v2_query(CustomEmoji.left_joins(:category).includes(:category), query)
    scope = scope.where(CustomEmoji.arel_table[:id].gt(params[:sinceId].to_i)) if params[:sinceId].present?
    scope = scope.where(CustomEmoji.arel_table[:id].lt(params[:untilId].to_i)) if params[:untilId].present?
    scope = apply_compat_pagination_dates(scope)
    limit = pagination_limit(default: 10, max: 100)
    total = scope.count
    page = [params[:page].to_i, 1].max
    emojis = apply_v2_sort(scope).limit(limit).offset(params[:page].present? ? (page - 1) * limit : 0).to_a

    render json: {
      emojis: emojis.map { |emoji| MisskeyCompat::EmojiSerializer.detailed_admin(emoji) },
      count: total > limit ? emojis.size : total,
      allCount: total,
      allPages: (total.to_f / limit).ceil,
    }
  end

  def create
    authorize :custom_emoji, :create?
    return unless require_keys!(:name, :fileId) && valid_name?(params[:name]) && valid_emoji_attributes?

    source = find_source_file
    return render_error('No such file', 'NO_SUCH_FILE', 404, id: NO_SUCH_FILE_IDS['create']) if source.nil?
    return render_error('Duplicate name', 'DUPLICATE_NAME', 400, id: DUPLICATE_NAME_ID) if CustomEmoji.local.exists?(shortcode: params[:name])
    return render_error('Unsupported file type', 'UNSUPPORTED_FILE_TYPE', 400, id: 'f7599d96-8750-af68-1633-9575d625c1a7') unless CustomEmoji::IMAGE_MIME_TYPES.include?(source.file_content_type)

    emoji = CustomEmoji.new(shortcode: params[:name], image: source.file, aliases: [], **emoji_attributes)
    emoji.save!
    log_action :create, emoji
    purge_emoji_cache

    render json: MisskeyCompat::EmojiSerializer.detailed(emoji)
  end

  def update
    authorize :custom_emoji, :update?
    return render_invalid_param('#/anyOf', 'must have required property id or name') unless params.key?(:id) || params.key?(:name)
    return if params.key?(:name) && !valid_name?(params[:name])
    return unless valid_emoji_attributes?

    emoji = params.key?(:id) ? CustomEmoji.local.find_by(id: mi_id_param(:id)) : CustomEmoji.local.find_by(shortcode: params[:name])
    return render_error('No such emoji', 'NO_SUCH_EMOJI', 404, id: NO_SUCH_EMOJI_IDS['update']) if emoji.nil?

    attributes = emoji_attributes
    if params.key?(:fileId)
      source = find_source_file
      return render_error('No such file', 'NO_SUCH_FILE', 404, id: NO_SUCH_FILE_IDS['update']) if source.nil?

      attributes[:image] = source.file
    end

    if params.key?(:id) && params.key?(:name) && params[:name] != emoji.shortcode
      return render_error('Emoji that have same name already exists', 'SAME_NAME_EMOJI_EXISTS', 400, id: '7180fe9d-1ee3-bff9-647d-fe9896d2ffb8') if CustomEmoji.local.exists?(shortcode: params[:name])

      attributes[:shortcode] = params[:name]
    end

    emoji.update!(attributes)
    log_action :update, emoji
    purge_emoji_cache

    head 204
  end

  def destroy
    authorize :custom_emoji, :destroy?

    emoji = CustomEmoji.find_by(id: mi_id_param(:id))
    return render_error('No such emoji', 'NO_SUCH_EMOJI', 404, id: NO_SUCH_EMOJI_IDS['destroy']) if emoji.nil?

    destroy_emojis([emoji])
    head 204
  end

  def destroy_bulk
    authorize :custom_emoji, :destroy?
    return unless (ids = require_ids!)

    destroy_emojis(CustomEmoji.where(id: ids).to_a)
    head 204
  end

  def copy
    authorize :custom_emoji, :copy?

    emoji = CustomEmoji.remote.find_by(id: mi_id_param(:emojiId))
    return render_error('No such emoji', 'NO_SUCH_EMOJI', 404, id: NO_SUCH_EMOJI_IDS['copy']) if emoji.nil?
    return render_error('Duplicate name', 'DUPLICATE_NAME', 400, id: DUPLICATE_NAME_ID) if CustomEmoji.local.exists?(shortcode: emoji.shortcode)

    copied = CustomEmoji.new(
      shortcode: emoji.shortcode, image: emoji.image, category_id: emoji.category_id, aliases: emoji.aliases,
      license: emoji.license, is_sensitive: emoji.is_sensitive, local_only: emoji.local_only
    )
    copied.save!
    log_action :create, copied
    purge_emoji_cache

    render json: { id: MisskeyCompat::MiId.encode(copied.id) }
  end

  def add_aliases
    bulk_update(require_aliases: true) { |emoji, aliases| (Array(emoji.aliases) + aliases).uniq }
  end

  def remove_aliases
    bulk_update(require_aliases: true) { |emoji, aliases| Array(emoji.aliases) - aliases }
  end

  def set_aliases
    bulk_update(require_aliases: true) { |_emoji, aliases| aliases.uniq }
  end

  def set_category
    return unless require_string_param!(:category, nullable: true)

    category_id = category_id_for(params[:category])
    bulk_update(attribute: :category_id) { category_id }
  end

  def set_license
    return unless require_string_param!(:license, nullable: true)

    bulk_update(attribute: :license) { params[:license] }
  end

  def import_zip
    authorize :custom_emoji, :create?
    return unless require_keys!(:fileId)

    drive_file = DriveFile.find_by(id: params[:fileId])
    return render_error('No such file', 'NO_SUCH_FILE', 404) if drive_file.nil?

    MisskeyCompatEmojiImportWorker.perform_async(drive_file.id, current_account.id)
    head 204
  end

  private

  def valid_name?(name)
    return true if name.is_a?(String) && name.match?(NAME_PATTERN)

    render_invalid_param('#/properties/name', 'must match pattern "^[a-zA-Z0-9_]+$"')
    false
  end

  def valid_emoji_attributes?
    return false if params.key?(:category) && !require_string_param!(:category, nullable: true)
    return false if params.key?(:license) && !require_string_param!(:license, nullable: true)
    return false unless require_string_array_param!(:aliases) && require_string_array_param!(:roleIdsThatCanBeUsedThisEmojiAsReaction)
    return false unless require_boolean_param!(:isSensitive) && require_boolean_param!(:localOnly)
    return true if params[:roleIdsThatCanBeUsedThisEmojiAsReaction].blank?

    render_invalid_param('#/properties/roleIdsThatCanBeUsedThisEmojiAsReaction', 'role-restricted emoji reactions are not supported on this server')
    false
  end

  def emoji_attributes
    attributes = {}
    attributes[:category_id] = category_id_for(params[:category]) if params.key?(:category)
    attributes[:aliases] = params[:aliases].compact_blank.uniq if params.key?(:aliases)
    attributes[:license] = params[:license] if params.key?(:license)
    attributes[:is_sensitive] = params[:isSensitive] if params.key?(:isSensitive)
    attributes[:local_only] = params[:localOnly] if params.key?(:localOnly)
    attributes
  end

  def category_id_for(name)
    name.blank? ? nil : CustomEmojiCategory.find_or_create_by!(name: name).id
  end

  def find_source_file
    file_id = params[:fileId]
    return nil if file_id.blank?

    source = DriveFile.find_by(id: file_id) || MediaAttachment.find_by(id: file_id)
    source&.file.present? ? source : nil
  end

  def require_ids!
    ids = mi_id_array_param(:ids)
    return ids unless ids.nil?

    render_invalid_param('#/properties/ids', 'must be array of strings')
    nil
  end

  def bulk_update(require_aliases: false, attribute: nil)
    authorize :custom_emoji, :update?
    return unless (ids = require_ids!)
    return if require_aliases && !(require_keys!(:aliases) && require_string_array_param!(:aliases, required: true))

    aliases = require_aliases ? params[:aliases].compact_blank : nil
    emojis = CustomEmoji.local.where(id: ids).to_a

    CustomEmoji.transaction do
      emojis.each do |emoji|
        value = yield(emoji, aliases)
        emoji.update!(require_aliases ? { aliases: value } : { attribute => value })
        log_action :update, emoji
      end
    end
    purge_emoji_cache

    head 204
  end

  def destroy_emojis(emojis)
    emojis.each do |emoji|
      emoji.destroy!
      log_action :destroy, emoji
    end
    purge_emoji_cache
  end

  def filter_local_query(scope, query)
    names = query.to_s.scan(/:([a-z0-9_]*):/).flatten
    return scope.where(shortcode: names) if names.any?

    pattern = "%#{CustomEmoji.sanitize_sql_like(query.to_s)}%"
    scope.left_joins(:category).where(
      'custom_emojis.shortcode LIKE :pattern OR custom_emoji_categories.name LIKE :pattern OR EXISTS (SELECT 1 FROM unnest(custom_emojis.aliases) AS alias WHERE alias LIKE :pattern)',
      pattern: pattern
    )
  end

  def filter_v2_query(scope, query)
    scope = scope.where('CAST(custom_emojis.updated_at AS DATE) >= ?', query[:updatedAtFrom]) if query[:updatedAtFrom].present?
    scope = scope.where('CAST(custom_emojis.updated_at AS DATE) <= ?', query[:updatedAtTo]) if query[:updatedAtTo].present?
    scope = like_any(scope, 'custom_emojis.shortcode', query[:name])
    scope = filter_host_type(scope, query)
    scope = like_any(scope, 'custom_emojis.uri', query[:uri])
    scope = like_any(scope, 'custom_emojis.image_remote_url', query[:publicUrl])
    scope = like_any(scope, 'custom_emojis.image_remote_url', query[:originalUrl])
    scope = like_any(scope, 'custom_emojis.image_content_type', query[:type])
    scope = like_any(scope, 'custom_emoji_categories.name', query[:category])
    scope = like_any(scope, 'custom_emojis.license', query[:license])
    scope = filter_aliases(scope, query[:aliases])
    scope = scope.where(is_sensitive: query[:isSensitive]) if [true, false].include?(query[:isSensitive])
    scope = scope.where(local_only: query[:localOnly]) if [true, false].include?(query[:localOnly])
    scope = scope.none if query[:roleIds].is_a?(Array) && query[:roleIds].any?
    scope
  end

  def filter_host_type(scope, query)
    case query[:hostType]
    when 'local'
      scope.where(domain: nil)
    when 'remote'
      query[:host].present? ? like_any(scope, 'custom_emojis.domain', query[:host]) : scope.where.not(domain: nil)
    else
      scope
    end
  end

  def like_patterns(words)
    words.to_s.split(/\s/).compact_blank.map { |word| "%#{CustomEmoji.sanitize_sql_like(word)}%" }
  end

  def like_any(scope, column, words)
    patterns = like_patterns(words)
    return scope if patterns.empty?

    scope.where("#{column} LIKE ANY (ARRAY[?]::text[])", patterns)
  end

  def filter_aliases(scope, words)
    patterns = like_patterns(words)
    return scope if patterns.empty?

    scope.where('EXISTS (SELECT 1 FROM unnest(custom_emojis.aliases) AS alias WHERE alias LIKE ANY (ARRAY[?]::text[]))', patterns)
  end

  def valid_sort_keys?
    return true unless params.key?(:sortKeys)

    params[:sortKeys].is_a?(Array) && params[:sortKeys].all? { |key| key.is_a?(String) && key.match?(/\A[+-]/) && SORT_COLUMNS.key?(key[1..]) }
  end

  def apply_v2_sort(scope)
    keys = params[:sortKeys].presence || ['-id']
    orders = keys.map { |key| Arel.sql("#{SORT_COLUMNS.fetch(key[1..])} #{key.start_with?('-') ? 'DESC' : 'ASC'}") }
    scope.reorder(*orders)
  end

  def purge_emoji_cache
    Rails.cache.delete('api/v1/custom_emojis/index')
    Rails.cache.delete_matched('emoji:*')
  end
end
