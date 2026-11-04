# frozen_string_literal: true

# The times of the last membership events applied for an account in a room. They outlive the membership,
# so an event that arrives late cannot undo a newer one.
#
# Clocks of different servers do not agree, so these are kept apart. last_roster_at only holds what the room's owner
# stated, for a server that mirrors the room. last_member_at only holds what the member's own server stated, for the
# server that owns the room.
class ChatRosterState < ApplicationRecord
  NO_OWNER_TIME = Time.utc(1970).freeze

  attribute :last_roster_at, default: -> { NO_OWNER_TIME }

  belongs_to :chat_conversation, inverse_of: :roster_states
  belongs_to :account
end
