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
    type = TYPE_MAP[notification.type]
    return nil if type.nil?

    body = {
      id: notification.id.to_s,
      createdAt: notification.created_at.iso8601,
      type: type,
    }

    from_account = notification.from_account
    if from_account
      body[:userId] = from_account.id.to_s
      body[:user] = MisskeyCompat::UserSerializer.serialize(from_account, viewer: recipient)
    end

    status = notification.target_status
    body[:note] = MisskeyCompat::NoteSerializer.serialize(status, current_account: recipient, embed_relations: false) if status

    reaction = reaction_for(notification)
    body[:reaction] = reaction if reaction

    {
      type: 'notification',
      body: body.compact,
      userId: recipient.id.to_s,
      dateTime: (notification.created_at.to_f * 1000).to_i,
    }
  end

  private

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
