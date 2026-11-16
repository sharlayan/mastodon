# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_roster_states
#
#  id                   :bigint(8)        not null, primary key
#  last_member_at       :datetime
#  last_roster_at       :datetime         not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint(8)        not null
#  chat_conversation_id :bigint(8)        not null
#
class ChatRosterState < ApplicationRecord
  NO_OWNER_TIME = Time.utc(1970).freeze

  attribute :last_roster_at, default: -> { NO_OWNER_TIME }

  belongs_to :chat_conversation, inverse_of: :roster_states
  belongs_to :account
end
