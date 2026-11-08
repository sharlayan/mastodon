# frozen_string_literal: true

class MisskeyCompat::ChatStreaming
  MESSAGE_EVENTS = %w(chat.message chat.message_update chat.message_delete chat.message_hide chat.reaction chat.reaction_delete chat.notification).freeze
  CONVERSATION_EVENTS = %w(chat.conversation_update chat.member_join chat.member_leave).freeze
  ROOM_DELETED_REASONS = [nil, 'deleted'].freeze

  class Lookups < ActiveSupport::CurrentAttributes
    attribute :records
  end

  Lookup = Struct.new(:message, :conversation, :direct_member_ids)

  class << self
    def broadcast(redis, viewer, event, payload)
      return unless Setting.chat_enabled && Setting.misskey_compat_enabled && viewer.local?

      data = payload.with_indifferent_access
      if event == 'chat.conversation_delete'
        publish(redis, "chatRoom:#{viewer.id}:#{data[:conversation_id]}", 'roomDeleted', nil, data[:conversation_id]) if ROOM_DELETED_REASONS.include?(data[:reason])
        return
      end

      return unless redis.exists?("subscribed:misskey:chatClient:#{viewer.id}")

      lookup = lookup_for(event, data)
      message = lookup.message
      conversation = lookup.conversation
      return if conversation.nil?

      channel = channel_for(viewer, lookup, event)
      return if channel.nil? || !redis.exists?("subscribed:misskey:#{channel}")
      return unless conversation.memberships.exists?(account: viewer)

      if event == 'chat.message_hide'
        return unless message&.account_id == viewer.id && message.hidden?
      elsif message && !ChatMessage.visible_to(viewer).exists?(id: message.id)
        return
      end

      type, body = event_payload(event, data, message, conversation, viewer)
      publish(redis, channel, type, body, conversation.id, message&.id) if type
    rescue => e
      Rails.logger.warn("[misskey_compat] chat broadcast failed for #{viewer.id}: #{e.class} #{e.message}")
    end

    private

    def lookup_for(event, data)
      key = [event, data[:message_id] || data[:id], data[:conversation_id], data[:edited_at], data[:deleted_at], data[:updated_at]].map(&:to_s)
      records = Lookups.records ||= {}
      records[key] ||= begin
        message = message_for(event, data)
        conversation = message&.chat_conversation || conversation_for(event, data)
        Lookup.new(message, conversation, conversation&.chat_direct? ? conversation.memberships.pluck(:account_id) : [])
      end
    end

    def message_for(event, data)
      return unless MESSAGE_EVENTS.include?(event)

      ChatMessage.find_by(id: data[:message_id] || data[:id])
    end

    def conversation_for(event, data)
      return unless CONVERSATION_EVENTS.include?(event)

      ChatConversation.find_by(id: data[:conversation_id] || data[:id])
    end

    def channel_for(viewer, lookup, event)
      return "chatMain:#{viewer.id}" if event == 'chat.notification'
      return "chatRoom:#{viewer.id}:#{lookup.conversation.id}" if lookup.conversation.chat_group?

      other_id = (lookup.direct_member_ids - [viewer.id]).first
      "chatUser:#{viewer.id}:#{other_id}" if other_id
    end

    def event_payload(event, data, message, conversation, viewer)
      case event
      when 'chat.message', 'chat.notification'
        [event == 'chat.message' ? 'message' : 'newChatMessage', MisskeyCompat::ChatSerializer.message(message, viewer: viewer)]
      when 'chat.message_update'
        serialized = MisskeyCompat::ChatSerializer.message(message, viewer: viewer)
        ['updated', { messageId: mid(message.id), text: serialized[:text], editedAt: serialized[:editedAt], emojis: serialized[:emojis] }]
      when 'chat.message_delete', 'chat.message_hide'
        ['deleted', mid(message.id)]
      when 'chat.reaction', 'chat.reaction_delete'
        actor = Account.find_by(id: data[:account_id] || data.dig(:account, :id))
        return if actor.nil?

        shortcode = ChatMessageReaction.shortcode_of(data[:reaction])
        reaction = shortcode ? ":#{shortcode}@#{actor.domain.presence || '.'}:" : data[:reaction]
        [event == 'chat.reaction' ? 'react' : 'unreact', { messageId: mid(message.id), reaction: reaction, user: MisskeyCompat::UserSerializer.serialize(actor, viewer: viewer) }]
      when 'chat.conversation_update'
        room = MisskeyCompat::ChatSerializer.room(conversation, viewer: viewer)
        ['roomUpdated', { roomId: mid(conversation.id), name: room[:name], description: room[:description], isArchived: room[:isArchived] }]
      when 'chat.member_join', 'chat.member_leave'
        [event == 'chat.member_join' ? 'membershipStarted' : 'membershipEnded', { userId: mid(data[:account_id]) }]
      end
    end

    def publish(redis, channel, type, body, conversation_id, message_id = nil)
      return unless redis.exists?("subscribed:misskey:#{channel}")

      payload = { type: type, body: body, conversationId: conversation_id.to_s, messageId: message_id&.to_s }
      redis.publish("misskey:#{channel}", JSON.generate(event: 'chat', payload: payload))
    end

    def mid(id)
      MisskeyCompat::MiId.encode(id)
    end
  end
end
