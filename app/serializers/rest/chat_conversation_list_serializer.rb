# frozen_string_literal: true

# The displayed last message can be hidden, so it is not a reliable page boundary.
class REST::ChatConversationListSerializer < REST::ChatConversationSerializer
  attributes :cursor_last_message_id

  def cursor_last_message_id
    object.last_message_id&.to_s
  end
end
