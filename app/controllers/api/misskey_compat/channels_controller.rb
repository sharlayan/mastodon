# frozen_string_literal: true

class Api::MisskeyCompat::ChannelsController < Api::MisskeyCompat::BaseController
  NO_SUCH_CHANNEL_IDS = {
    'show' => '6f6c314b-7486-4897-8966-c04a66a02923',
    'update' => 'f9c5467f-d492-4c3c-9a8d-a70dacc86512',
  }.freeze
  NO_SUCH_FILE_IDS = {
    'create' => 'cd1e9f3e-5a12-4ab4-96f6-5d0a2cc32050',
    'update' => 'e86c14a4-0da2-4032-8df3-e737a04c7f3b',
  }.freeze
  UPDATE_ACCESS_DENIED_ID = '1fb7cb09-d46a-4fdf-b8df-057788cce513'
  FEATURED_LIMIT = 10
  SEARCH_TYPES = %w(nameAndDescription nameOnly).freeze

  OPTIONAL_AUTHENTICATION_ACTIONS = %i(show featured search).freeze
  USER_ACTIONS = %i(create update owned).freeze

  requires_write_scope :create, :update
  requires_misskey_permission 'read:account', *OPTIONAL_AUTHENTICATION_ACTIONS
  requires_misskey_permission 'read:channels', :owned
  requires_misskey_permission 'write:channels', :create, :update

  before_action :require_user!, only: USER_ACTIONS
  before_action :require_user_if_authenticated!, only: OPTIONAL_AUTHENTICATION_ACTIONS
  before_action :require_object_body!
  before_action :set_channel, only: [:show, :update]

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

  private

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
