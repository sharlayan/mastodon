# frozen_string_literal: true

class ChatRosterState < ApplicationRecord
  NO_OWNER_TIME = Time.utc(1970).freeze

  attribute :last_roster_at, default: -> { NO_OWNER_TIME }

  belongs_to :chat_conversation, inverse_of: :roster_states
  belongs_to :account
end
