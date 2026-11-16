# frozen_string_literal: true

# == Schema Information
#
# Table name: voice_call_remote_sessions
#
#  id                   :bigint(8)        not null, primary key
#  expires_at           :datetime         not null
#  identity             :string           not null
#  origin               :string           not null
#  room_name            :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint(8)        not null
#  chat_conversation_id :bigint(8)        not null
#
class VoiceCallRemoteSession < ApplicationRecord
  LIFETIME = 12.hours

  belongs_to :account
  belongs_to :chat_conversation

  scope :expired, -> { where(expires_at: ...Time.now.utc) }
end
