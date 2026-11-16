# frozen_string_literal: true

class Api::MisskeyCompat::ChannelsController < Api::MisskeyCompat::BaseController
  NO_SUCH_CHANNEL_IDS = {
    'show' => '6f6c314b-7486-4897-8966-c04a66a02923',
    'update' => 'f9c5467f-d492-4c3c-9a8d-a70dacc86512',
    'follow' => 'c0031718-d573-4e85-928e-10039f1fbb68',
    'unfollow' => '19959ee9-0153-4c51-bbd9-a98c49dc59d6',
    'favorite' => '4938f5f3-6167-4c04-9149-6607b7542861',
    'unfavorite' => '353c68dd-131a-476c-aa99-88a345e83668',
    'mute_create' => '7174361e-d58f-31d6-2e7c-6fb830786a3f',
    'mute_delete' => 'e7998769-6e94-d9c2-6b8f-94a527314aba',
    'timeline' => '4d0eeeba-a02c-4c3c-9966-ef60d38d2e7f',
  }.freeze
  NO_SUCH_FILE_IDS = {
    'create' => 'cd1e9f3e-5a12-4ab4-96f6-5d0a2cc32050',
    'update' => 'e86c14a4-0da2-4032-8df3-e737a04c7f3b',
  }.freeze
  UPDATE_ACCESS_DENIED_ID = '1fb7cb09-d46a-4fdf-b8df-057788cce513'
  ALREADY_MUTING_ID = '5a251978-769a-da44-3e89-3931e43bb592'
  EXPIRES_AT_IS_PAST_ID = '42b32236-df2c-a45f-fdbf-def67268f749'
  NOT_MUTING_ID = '14d55962-6ea8-d990-1333-d6bef78dc2ab'
  MAX_EXPIRES_AT = 253_402_300_799_000
  FEATURED_LIMIT = 10
  TIMELINE_SCAN_LIMIT = 1_000
  SEARCH_TYPES = %w(nameAndDescription nameOnly).freeze

  OPTIONAL_AUTHENTICATION_ACTIONS = %i(show featured search timeline).freeze
  WRITE_ACTIONS = %i(create update follow unfollow favorite unfavorite mute_create mute_delete).freeze
  USER_ACTIONS = (WRITE_ACTIONS + %i(owned followed my_favorites mute_list)).freeze

  requires_write_scope(*WRITE_ACTIONS)
  requires_misskey_permission 'read:account', *OPTIONAL_AUTHENTICATION_ACTIONS
  requires_misskey_permission 'read:channels', :owned, :followed, :my_favorites, :mute_list
  requires_misskey_permission 'write:channels', *WRITE_ACTIONS

  before_action :require_user!, only: USER_ACTIONS
  before_action :require_user_if_authenticated!, only: OPTIONAL_AUTHENTICATION_ACTIONS
  before_action :require_object_body!
  before_action :set_channel, only: [:show, :update, :follow, :unfollow, :favorite, :unfavorite, :mute_create, :mute_delete, :timeline]

  def show
    render json: serialize(@channel, detailed: true)
  end

  def create
    return if rate_limited?(:misskey_compat_channel_create)
    return unless valid_channel_params?(required_name: true)

    banner = resolve_banner
    return if banner == false

    channel = MisskeyChannel.create!(
      account: current_account,
      name: params[:name],
      description: params[:description],
      banner_drive_file: banner,
      color: params[:color].presence || MisskeyChannel::DEFAULT_COLOR,
      sensitive: params[:isSensitive] || false,
      allow_renote_to_external: params[:allowRenoteToExternal].nil? || params[:allowRenoteToExternal]
    )

    render json: serialize(channel)
  end

  def update
    return render_error('You do not have edit privilege of the channel', 'ACCESS_DENIED', 403, id: UPDATE_ACCESS_DENIED_ID) unless @channel.editable_by?(current_account)
    return unless valid_channel_params?(required_name: false) && valid_update_params?

    banner = resolve_banner
    return if banner == false

    @channel.update!(channel_attributes(banner))
    render json: serialize(@channel.reload)
  end

  def featured
    channels = MisskeyChannel.unarchived.where.not(last_noted_at: nil).order(last_noted_at: :desc).limit(FEATURED_LIMIT)
    render json: serialize_many(channels)
  end

  def owned
    render json: serialize_many(paginate(MisskeyChannel.unarchived.where(account: current_account), MisskeyChannel.arel_table[:id]))
  end

  def search
    return render_invalid_param('#/properties/query', 'must be string') unless params[:query].is_a?(String)
    return render_invalid_param('#/properties/type', 'must be one of nameAndDescription, nameOnly') if params.key?(:type) && SEARCH_TYPES.exclude?(params[:type])

    render json: serialize_many(paginate(search_scope, MisskeyChannel.arel_table[:id]))
  end

  def follow
    following = current_account.with_lock do
      MisskeyChannelFollowing.find_or_create_by!(account: current_account, misskey_channel: @channel)
    end
    return render_error('You are already following that channel', 'ALREADY_FOLLOWING', 400, id: '7db31665-651e-40c1-8e6e-28e9ad829a2d') unless following.previously_new_record?

    head 204
  end

  def unfollow
    MisskeyChannelFollowing.where(account: current_account, misskey_channel: @channel).delete_all
    head 204
  end

  def favorite
    MisskeyChannelFavorite.find_or_create_by!(account: current_account, misskey_channel: @channel)
    head 204
  end

  def unfavorite
    MisskeyChannelFavorite.where(account: current_account, misskey_channel: @channel).delete_all
    head 204
  end

  def followed
    followings = paginate(MisskeyChannelFollowing.where(account: current_account), MisskeyChannelFollowing.arel_table[:misskey_channel_id]).includes(:misskey_channel)
    render json: serialize_many(followings.map(&:misskey_channel))
  end

  def my_favorites
    favorites = MisskeyChannelFavorite.where(account: current_account).includes(:misskey_channel).order(:id)
    render json: serialize_many(favorites.map(&:misskey_channel))
  end

  def mute_create
    expires_at = mute_expires_at
    return if expires_at == false

    muting = MisskeyChannelMuting.find_or_initialize_by(account: current_account, misskey_channel: @channel)
    return render_error('You are already muting that user', 'ALREADY_MUTING_CHANNEL', 400, id: ALREADY_MUTING_ID) if muting.persisted? && !muting.expired?
    return render_error('Cannot set past date to "expiresAt"', 'EXPIRES_AT_IS_PAST', 400, id: EXPIRES_AT_IS_PAST_ID) if expires_at.present? && expires_at <= Time.now.utc

    muting.update!(expires_at: expires_at)
    head 204
  end

  def mute_delete
    muting = MisskeyChannelMuting.active.find_by(account: current_account, misskey_channel: @channel)
    return render_error('You are not muting that channel', 'NOT_MUTING_CHANNEL', 400, id: NOT_MUTING_ID) if muting.nil?

    muting.destroy!
    head 204
  end

  def mute_list
    channels = MisskeyChannel.where(id: MisskeyChannelMuting.active.where(account: current_account).select(:misskey_channel_id)).order(:id)
    render json: serialize_many(channels)
  end

  def timeline
    return if current_account.nil? && rate_limited?(:misskey_compat_api)

    statuses = visible_timeline_statuses
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  private

  def timeline_scope
    notes = MisskeyChannelNote.arel_table
    scope = Status.joins(Status.arel_table.join(notes).on(notes[:status_id].eq(Status.arel_table[:id])).join_sources)
      .where(misskey_channel_notes: { misskey_channel_id: @channel.id })
    return scope if current_account.nil?

    scope = scope.not_excluded_by_account(current_account)
    muted_channel_ids = MisskeyChannelMuting.channel_ids_for(current_account) - [@channel.id]
    return scope if muted_channel_ids.empty?

    scope.where.not(MisskeyChannelNote.where(misskey_channel_id: muted_channel_ids).linked_status_condition(Status.arel_table[:reblog_of_id]))
  end

  def visible_timeline_statuses
    column = Status.arel_table[:id]
    upper = params[:untilId].presence || snowflake_id_at(params[:untilDate])
    lower = params[:sinceId].presence || snowflake_id_at(params[:sinceDate])
    forward = lower.present? && upper.blank?
    limit = pagination_limit(default: 10, max: 100)
    scope = timeline_scope
    scope = scope.where(column.lt(upper.to_i)) if upper.present?
    scope = scope.where(column.gt(lower.to_i)) if lower.present?
    scope = scope.reorder(column.public_send(forward ? :asc : :desc))
    statuses = []
    cursor = nil
    scanned = 0

    while statuses.size < limit && scanned < TIMELINE_SCAN_LIMIT
      batch = scope
      batch = batch.where(forward ? column.gt(cursor) : column.lt(cursor)) if cursor
      page = batch.limit([limit * 2, 100].min).to_a
      break if page.empty?

      relations = MisskeyCompat::SerializationContext.new(current_account: current_account).prime_relations(page)
      statuses.concat(page.select { |status| relations.visible?(status) })
      scanned += page.size
      cursor = page.last.id
    end

    statuses.first(limit)
  end

  def mute_expires_at
    value = params[:expiresAt]
    return nil if value.nil?
    return Time.zone.at(value / 1000.0) if value.is_a?(Integer) && value.abs <= MAX_EXPIRES_AT

    render_invalid_param('#/properties/expiresAt', 'must be integer')
    false
  end

  def require_object_body!
    object_body!
  end

  def set_channel
    @channel = MisskeyChannel.find_by(id: params[:channelId]) if compat_id?(params[:channelId])
    render_no_such_channel(NO_SUCH_CHANNEL_IDS[action_name]) if @channel.nil?
  end

  def render_no_such_channel(id)
    render_error('No such channel', 'NO_SUCH_CHANNEL', 404, id: id)
  end

  def search_scope
    scope = MisskeyChannel.unarchived
    return scope if params[:query].empty?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query])}%"
    table = MisskeyChannel.arel_table
    condition = table[:name].matches(pattern)
    condition = condition.or(table[:description].matches(pattern)) unless params[:type] == 'nameOnly'
    scope.where(condition)
  end

  def paginate(scope, column, default: 5, max: 100)
    upper = params[:untilId].presence || snowflake_id_at(params[:untilDate])
    lower = params[:sinceId].presence || snowflake_id_at(params[:sinceDate])
    scope = scope.where(column.lt(upper.to_i)) if upper.present?
    scope = scope.where(column.gt(lower.to_i)) if lower.present?
    scope.reorder(column.public_send(lower.present? && upper.blank? ? :asc : :desc)).limit(pagination_limit(default: default, max: max))
  end

  def snowflake_id_at(value)
    Mastodon::Snowflake.id_at(compat_time(value), with_random: false) if value.present?
  end

  def valid_channel_params?(required_name:)
    valid_string?(:name, 1, MisskeyChannel::NAME_LENGTH_LIMIT, required: required_name) &&
      valid_string?(:description, 0, MisskeyChannel::DESCRIPTION_LENGTH_LIMIT, nullable: true) &&
      valid_string?(:color, 1, MisskeyChannel::COLOR_LENGTH_LIMIT) &&
      valid_id?(:bannerId) &&
      %i(isSensitive allowRenoteToExternal).all? { |key| valid_boolean?(key) }
  end

  def valid_update_params?
    valid_boolean?(:isArchived) && valid_pinned_note_ids?
  end

  def valid_string?(key, min, max, required: false, nullable: false)
    return true if !params.key?(key) && !required

    value = params[key]
    return true if value.nil? && nullable
    return true if value.is_a?(String) && value.length.between?(min, max)

    render_invalid_param("#/properties/#{key}", "must be a string of #{min} to #{max} characters")
    false
  end

  def valid_id?(key)
    value = params[key]
    return true if value.nil? || value.is_a?(String)

    render_invalid_param("#/properties/#{key}", 'must be string')
    false
  end

  def valid_boolean?(key)
    return true if [true, false, nil].include?(params[key])

    render_invalid_param("#/properties/#{key}", 'must be boolean')
    false
  end

  def valid_pinned_note_ids?
    return true unless params.key?(:pinnedNoteIds)

    ids = params[:pinnedNoteIds]
    if ids.is_a?(Array) && ids.all?(String)
      @pinned_status_ids = ids.map { |id| MisskeyCompat::MiId.decode(id) }
      return true if @pinned_status_ids.all? { |id| compat_id?(id) }
    end

    render_invalid_param('#/properties/pinnedNoteIds', 'must be an array of note ids')
    false
  end

  def resolve_banner
    return nil if params[:bannerId].nil?

    banner = DriveFile.find_by(id: params[:bannerId], account: current_account) if Setting.drive_enabled && compat_id?(params[:bannerId])
    return banner if banner

    render_error('No such file', 'NO_SUCH_FILE', 404, id: NO_SUCH_FILE_IDS[action_name])
    false
  end

  def channel_attributes(banner)
    attributes = {
      name: params[:name],
      color: params[:color],
      archived: params[:isArchived],
      sensitive: params[:isSensitive],
      allow_renote_to_external: params[:allowRenoteToExternal],
      pinned_status_ids: @pinned_status_ids&.map(&:to_i),
    }.compact
    attributes[:description] = params[:description] if params.key?(:description)
    attributes[:banner_drive_file] = banner if params.key?(:bannerId)
    attributes
  end

  def serialize(channel, detailed: false)
    MisskeyCompat::ChannelSerializer.serialize(channel, current_account: current_account, detailed: detailed)
  end

  def serialize_many(channels)
    MisskeyCompat::ChannelSerializer.serialize_many(channels, current_account: current_account)
  end
end
