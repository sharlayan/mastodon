# frozen_string_literal: true

# What a message said before an edit, kept while the server preserves what its users delete.
class ChatMessageEdit < ApplicationRecord
  belongs_to :chat_message, inverse_of: :edits
end
