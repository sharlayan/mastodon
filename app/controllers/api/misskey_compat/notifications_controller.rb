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
    notifications = filter_types(scope, include_types, exclude_types).joins(:from_account).includes(:from_account).order(id: direction).limit(limit).to_a
    notifications.group_by(&:type).each do |type, records|
      associations = Notification::TARGET_STATUS_INCLUDES_BY_TYPE[type]
      ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call if associations
    end

    statuses = notifications.filter_map { |notification| note_status(notification, notification.target_status) }
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    notifications.filter_map { |notification| serialize(notification, context: context) }
  end

  def filter_types(scope, include_types, exclude_types)
    types = include_types || (NOTIFICATION_TYPES - Array(exclude_types))
    db_types = TYPE_MAP.filter_map { |type, name| type if types.include?(name) || (type == :mention && types.include?('reply')) }
    scope = scope.where(type: db_types)
    return scope if types.include?('mention') == types.include?('reply')

    reply_mention = Mention.joins(:status).where(Mention.arel_table[:id].eq(Notification.arel_table[:activity_id])).where.not(statuses: { in_reply_to_id: nil }).arel.exists
    mentions = scope.where(type: :mention)
    mentions = types.include?('reply') ? mentions.where(reply_mention) : mentions.where.not(reply_mention)
    scope.where.not(type: :mention).or(mentions)
  end

  def advance_notification_marker!
    latest_id = current_account.notifications.maximum(:id)
    return if latest_id.nil?

    marker = current_user.markers.find_or_create_by(timeline: 'notifications')
    marker.update(last_read_id: latest_id) if marker.last_read_id.to_i < latest_id
  rescue ActiveRecord::StaleObjectError
    nil
  end

  def serialize(notification, context:)
    status = notification.target_status
    type = notification_type(notification, status)
    return nil if type.nil? || notification.from_account.nil?

    data = {
      id: MisskeyCompat::MiId.encode(notification.id),
      createdAt: notification.created_at.iso8601,
      type: type,
      userId: MisskeyCompat::MiId.encode(notification.from_account.id),
      user: context.user(notification.from_account),
    }

    note = note_status(notification, status)
    data[:note] = MisskeyCompat::NoteSerializer.serialize(note, context: context) if note
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
