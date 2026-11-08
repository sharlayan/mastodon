# frozen_string_literal: true

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
    shared = @messages[message.id] ||= shared_message(message)
    return shared if message.media_attachments.empty?

    shared.merge(media_attachments: message.media_attachments.map { |media| REST::MediaAttachmentSerializer.new(media, current_account: account).as_json })
  end

  def shared_message(message)
    ActiveRecord::Associations::Preloader.new(records: message.media_attachments.to_a, associations: :chat_message_media_attachments).call
    REST::ChatMessageSerializer.new(message).as_json
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
