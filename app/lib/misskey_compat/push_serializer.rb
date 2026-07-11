# frozen_string_literal: true

class MisskeyCompat::PushSerializer
  include RoutingHelper

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

  def self.serialize(notification, recipient)
    new.serialize(notification, recipient)
  end

  def serialize(notification, recipient)
    status = notification.target_status
    type = notification_type(notification, status)
    return nil if type.nil?

    body = {
      id: MisskeyCompat::MiId.encode(notification.id),
      createdAt: notification.created_at.iso8601,
      type: type,
    }

    from_account = notification.from_account
    if from_account
      body[:userId] = MisskeyCompat::MiId.encode(from_account.id)
      body[:user] = MisskeyCompat::UserSerializer.serialize(from_account, viewer: recipient)
    end

    body[:note] = MisskeyCompat::NoteSerializer.serialize(status, current_account: recipient, embed_relations: false) if status

    reaction = reaction_for(notification)
    body[:reaction] = reaction if reaction

    {
      type: 'notification',
      body: body.compact,
      userId: MisskeyCompat::MiId.encode(recipient.id),
      dateTime: (notification.created_at.to_f * 1000).to_i,
    }
  end

  private

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
      reaction = notification.respond_to?(:status_reaction) ? notification.status_reaction : nil
      return nil if reaction.nil?

      custom = reaction.custom_emoji
      return reaction.name if custom.nil?

      host = custom.domain.presence || '.'
      ":#{reaction.name}@#{host}:"
    end
  end
end
