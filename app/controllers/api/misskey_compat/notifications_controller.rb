# frozen_string_literal: true

class Api::MisskeyCompat::NotificationsController < Api::MisskeyCompat::BaseController
  requires_write_scope :mark_all_as_read, :create
  requires_misskey_permission 'read:notifications', :index
  requires_misskey_permission 'write:notifications', :mark_all_as_read, :create

  include RoutingHelper

  before_action :require_user!

  TYPE_MAP = {
    mention: 'mention',
    status: 'note',
    reblog: 'renote',
    quote: 'quote',
    follow: 'follow',
    follow_request: 'receiveFollowRequest',
    follow_accepted: 'followRequestAccepted',
    favourite: 'reaction',
    reaction: 'reaction',
    poll: 'pollEnded',
  }.freeze
  NOTIFICATION_TYPES = %w(note follow mention reply renote quote reaction pollEnded scheduledNotePosted scheduledNotePostFailed receiveFollowRequest followRequestAccepted roleAssigned chatRoomInvitationReceived achievementEarned exportCompleted login createToken app test).freeze
  OBSOLETE_NOTIFICATION_TYPES = %w(pollVote groupInvited).freeze

  def index
    include_types = params[:includeTypes]
    exclude_types = params[:excludeTypes]
    return unless valid_types?(include_types, :includeTypes) && valid_types?(exclude_types, :excludeTypes)

    if include_types == [] || (NOTIFICATION_TYPES - Array(exclude_types)).empty?
      render json: []
      return
    end

    scope = current_account.notifications.where(type: TYPE_MAP.keys)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('notifications.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope = scope.where(created_at: ...compat_time(params[:untilDate])) if params[:untilId].blank? && params[:untilDate].present?
    scope = scope.where('notifications.created_at > ?', compat_time(params[:sinceDate])) if params[:sinceId].blank? && params[:sinceDate].present?
    direction = (params[:sinceId].present? || params[:sinceDate].present?) && params[:untilId].blank? && params[:untilDate].blank? ? :asc : :desc
    limit = pagination_limit(default: 10, max: 100)
    notifications = filtered_notifications(scope, include_types, exclude_types, direction, limit)

    advance_notification_marker! unless params[:markAsRead] == false
    render json: notifications
  end

  def mark_all_as_read
    advance_notification_marker!
    head 204
  end

  def create
    head 204
  end

  private

  def valid_types?(types, param)
    return true if types.nil? || (types.is_a?(Array) && types.all? { |type| (NOTIFICATION_TYPES + OBSOLETE_NOTIFICATION_TYPES).include?(type) })

    render_invalid_param("#/#{param}", 'must be an array of notification types')
    false
  end

  def filtered_notifications(scope, include_types, exclude_types, direction, limit)
    results = []
    cursor = nil

    loop do
      batch_scope = scope
      batch_scope = batch_scope.where("notifications.id #{direction == :asc ? '>' : '<'} ?", cursor) if cursor
      batch = batch_scope.includes(:from_account).order(id: direction).limit(100).to_a
      break if batch.empty?

      batch.each do |notification|
        value = serialize(notification)
        next if value.nil?
        next if include_types && !include_types.include?(value[:type])
        next if include_types.nil? && exclude_types&.include?(value[:type])

        results << value
        break if results.size == limit
      end

      break if results.size == limit || batch.size < 100

      cursor = batch.last.id
    end

    results
  end

  def advance_notification_marker!
    latest_id = current_account.notifications.maximum(:id)
    return if latest_id.nil?

    marker = current_user.markers.find_or_create_by(timeline: 'notifications')
    marker.update(last_read_id: latest_id) if marker.last_read_id.to_i < latest_id
  rescue ActiveRecord::StaleObjectError
    nil
  end

  def serialize(notification)
    status = notification.target_status
    type = notification_type(notification, status)
    return nil if type.nil? || notification.from_account.nil?

    data = {
      id: MisskeyCompat::MiId.encode(notification.id),
      createdAt: notification.created_at.iso8601,
      type: type,
      userId: MisskeyCompat::MiId.encode(notification.from_account.id),
      user: MisskeyCompat::UserSerializer.serialize(notification.from_account),
    }

    note = note_status(notification, status)
    data[:note] = MisskeyCompat::NoteSerializer.serialize(note, current_account: current_account) if note
    data[:reaction] = reaction_for(notification)
    data.compact
  end

  def note_status(notification, status)
    return notification.status if notification.type == :reblog

    status
  end

  def notification_type(notification, status)
    type = TYPE_MAP[notification.type]
    return type unless type == 'mention'

    status&.in_reply_to_id.present? ? 'reply' : 'mention'
  end

  def reaction_for(notification)
    case notification.type
    when :favourite
      '❤'
    when :reaction
      reaction = notification.status_reaction
      return nil if reaction.nil?

      custom = reaction.custom_emoji
      return reaction.name if custom.nil?

      host = custom.domain.presence || '.'
      ":#{reaction.name}@#{host}:"
    end
  end
end
