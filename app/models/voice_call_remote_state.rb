# frozen_string_literal: true

# == Schema Information
#
# Table name: voice_call_remote_states
#
#  id                   :bigint(8)        not null, primary key
#  participants         :jsonb            not null
#  remote_updated_at    :bigint(8)        not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  chat_conversation_id :bigint(8)        not null
#
class VoiceCallRemoteState < ApplicationRecord
  STALE_AFTER = 10.minutes

  belongs_to :chat_conversation

  def current_participants
    return [] if participants.blank?
    return [] if updated_at < STALE_AFTER.ago

    participants
  end
end
