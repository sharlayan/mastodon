# frozen_string_literal: true

class Api::MisskeyCompat::NotificationsController < Api::MisskeyCompat::BaseController
  include RoutingHelper

  before_action :require_user!

  TYPE_MAP = {
    mention: 'mention',
    reblog: 'renote',
    quote: 'quote',
    follow: 'follow',
    follow_request: 'receiveFollowRequest',
    follow_accepted: 'followRequestAccepted',
    favourite: 'reaction',
    reaction: 'reaction',
    poll: 'pollEnded',
  }.freeze

  def index
    scope = current_account.notifications.where(type: TYPE_MAP.keys)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('notifications.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    notifications = scope.includes(:from_account).order(id: :desc).limit(pagination_limit)

    render json: notifications.filter_map { |notification| serialize(notification) }
  end

  private

  def serialize(notification)
    type = TYPE_MAP[notification.type]
    return nil if type.nil? || notification.from_account.nil?

    data = {
      id: MisskeyCompat::MiId.encode(notification.id),
      createdAt: notification.created_at.iso8601,
      type: type,
      userId: MisskeyCompat::MiId.encode(notification.from_account.id),
      user: MisskeyCompat::UserSerializer.serialize(notification.from_account),
    }

    status = notification.target_status
    data[:note] = MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account) if status
    data[:reaction] = reaction_for(notification)
    data.compact
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
