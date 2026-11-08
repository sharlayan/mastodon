# frozen_string_literal: true

class ChatMessageEdit < ApplicationRecord
  belongs_to :chat_message, inverse_of: :edits
end
