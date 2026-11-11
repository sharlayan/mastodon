# frozen_string_literal: true

# == Schema Information
#
# Table name: voice_call_allocations
#
#  id                      :bigint(8)        not null, primary key
#  generation              :string           not null
#  participants            :jsonb            not null
#  refreshed_at            :datetime
#  renewed_at              :datetime
#  revision                :string
#  room_key                :string           not null
#  slots                   :integer          not null
#  state                   :string           default("pending"), not null
#  unavailable             :boolean          default(FALSE), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  chat_conversation_id    :bigint(8)
#  remote_id               :string
#  voice_relay_provider_id :bigint(8)        not null
#
class VoiceCallAllocation < ApplicationRecord
  STATES = %w(pending active ending ended).freeze
  REMOTE_ID_PATTERN = /\A[a-zA-Z0-9-]{1,128}\z/

  belongs_to :chat_conversation, optional: true
  belongs_to :voice_relay_provider

  validates :state, inclusion: { in: STATES }
  validates :slots, numericality: { only_integer: true, greater_than: 0 }

  scope :unfinished, -> { where.not(state: 'ended') }
  scope :active, -> { where(state: 'active') }

  STATES.each do |name|
    define_method(:"#{name}?") { state == name }
  end

  def remote_path(suffix = '')
    raise Sharlayan::VoiceRelay::Error.new('ALLOCATION_CONFLICT', 409) unless REMOTE_ID_PATTERN.match?(remote_id.to_s)

    "/allocations/#{remote_id}#{suffix}"
  end

  def participant_account_ids
    participants.filter_map { |participant| participant['account_id'] }
  end

  def lock_key
    chat_conversation_id ? "voice_call:#{chat_conversation_id}" : "voice_call_allocation:#{id}"
  end
end
