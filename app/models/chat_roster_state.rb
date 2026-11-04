# frozen_string_literal: true

# The time of the last membership event applied for an account in a room. It outlives the membership,
# so an event that arrives late cannot undo a newer one.
class ChatRosterState < ApplicationRecord
  belongs_to :chat_conversation, inverse_of: :roster_states
  belongs_to :account
end
