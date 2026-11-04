# frozen_string_literal: true

# Renders one object for every member of a conversation. A big room would otherwise repeat the whole
# serialization per member during the request, when only a few values depend on who is looking.
class Sharlayan::ChatBroadcastPayload
  def initialize(object, serializer)
    @object = object
    @serializer = serializer
    @messages = {}
  end

  def for(account)
    if @serializer == REST::ChatMessageSerializer
      message_for(@object, account)
    elsif @serializer == REST::ChatConversationSerializer
      conversation_for(account)
    elsif @serializer
      @serializer.new(@object, current_account: account).as_json
    else
      @object
    end
  end

  private

  def message_for(message, account)
    shared = @messages[message.id] ||= REST::ChatMessageSerializer.new(message).as_json
    return shared if message.media_attachments.empty?

    shared.merge(media_attachments: message.media_attachments.map { |media| REST::MediaAttachmentSerializer.new(media, current_account: account).as_json })
  end

  def conversation_for(account)
    serializer = REST::ChatConversationSerializer.new(@object, current_account: account)
    last_message = serializer.visible_last_message

    shared_conversation.merge(
      unread: serializer.unread,
      muted: serializer.muted,
      current_role: serializer.current_role,
      last_message: last_message && message_for(last_message, account)
    )
  end

  def shared_conversation
    @shared_conversation ||= REST::ChatConversationSerializer.new(@object).as_json
  end
end
