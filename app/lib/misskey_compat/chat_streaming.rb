# frozen_string_literal: true

class MisskeyCompat::ChatStreaming
  MESSAGE_EVENTS = %w(chat.message chat.message_update chat.message_delete chat.message_hide chat.reaction chat.reaction_delete chat.notification).freeze

  class << self
    def broadcast(redis, viewer, event, payload)
      return unless Setting.chat_enabled && Setting.misskey_compat_enabled && viewer.local?

      data = payload.with_indifferent_access
      if event == 'chat.conversation_delete'
        publish(redis, "chatRoom:#{viewer.id}:#{data[:conversation_id]}", 'roomDeleted', nil, data[:conversation_id])
        return
      end

      message = message_for(event, data)
      conversation = message&.chat_conversation || conversation_for(event, data)
      return unless conversation&.memberships&.exists?(account: viewer)

      if event == 'chat.message_hide'
        return unless message&.account_id == viewer.id && message.hidden?
      elsif message && !ChatMessage.visible_to(viewer).exists?(id: message.id)
        return
      end

      channel = channel_for(viewer, conversation, event)
      return if channel.nil? || !redis.exists?("subscribed:misskey:#{channel}")

      type, body = event_payload(event, data, message, conversation, viewer)
      publish(redis, channel, type, body, conversation.id, message&.id) if type
    rescue => e
      Rails.logger.warn("[misskey_compat] chat broadcast failed for #{viewer.id}: #{e.class} #{e.message}")
    end

    private

    def message_for(event, data)
      return unless MESSAGE_EVENTS.include?(event)

      ChatMessage.find_by(id: data[:message_id] || data[:id])
    end

    def conversation_for(event, data)
      return unless %w(chat.conversation_update chat.member_join chat.member_leave).include?(event)

      ChatConversation.find_by(id: data[:conversation_id] || data[:id])
    end

    def channel_for(viewer, conversation, event)
      return "chatMain:#{viewer.id}" if event == 'chat.notification'
      return "chatRoom:#{viewer.id}:#{conversation.id}" if conversation.chat_group?

      other_id = conversation.memberships.where.not(account_id: viewer.id).pick(:account_id)
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
