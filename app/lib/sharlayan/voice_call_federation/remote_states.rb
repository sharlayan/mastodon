# frozen_string_literal: true

module Sharlayan
  module VoiceCallFederation
    class RemoteStates
      MAX_AHEAD = 5.minutes
      ACTIVE_MAX_AGE = 7.minutes
      EMPTY_MAX_AGE = 2.days
      MAX_PARTICIPANTS = 1001
      BOOLEANS = [true, false].freeze

      class << self
        def store(conversation, participants, updated_at)
          return :disabled unless Sharlayan::VoiceCallService.remote_available?(conversation)

          now = (Time.now.to_f * 1000).to_i
          return :ahead if updated_at > now + MAX_AHEAD.in_milliseconds
          return :old if updated_at < now - (participants.any? ? ACTIVE_MAX_AGE : EMPTY_MAX_AGE).in_milliseconds

          entries = admitted(conversation, participants)
          changed = write(conversation, entries, updated_at)
          return :stale if changed.nil?

          Sharlayan::VoiceCallService.publish_state(conversation) if changed
          :stored
        end

        def parse_participants(value, identity_key:)
          return unless value.is_a?(Array) && value.size <= MAX_PARTICIPANTS && value.all? { |participant| valid_participant?(participant, identity_key) }

          value.map do |participant|
            { identity: participant[identity_key], screen_sharing: participant['screenSharing'], mic_muted: participant['micMuted'] == true, deafened: participant['deafened'] == true }
          end
        end

        private

        def valid_participant?(participant, identity_key)
          participant.is_a?(Hash) && participant[identity_key].is_a?(String) && participant[identity_key].length <= 2048 && BOOLEANS.include?(participant['screenSharing'])
        end

        def write(conversation, entries, updated_at)
          VoiceCallRemoteState.transaction do
            state = VoiceCallRemoteState.lock.find_or_initialize_by(chat_conversation_id: conversation.id)
            next nil if state.persisted? && state.remote_updated_at >= updated_at

            changed = state.new_record? || state.current_participants != entries
            state.participants = entries
            state.remote_updated_at = updated_at
            state.updated_at = Time.now.utc
            state.save!
            changed
          end
        rescue ActiveRecord::RecordNotUnique
          nil
        end

        def admitted(conversation, participants)
          member_ids = conversation.memberships.pluck(:account_id).to_set
          ActiveRecord::Base.cache do
            participants.uniq { |participant| participant[:identity] }.first(MAX_PARTICIPANTS).filter_map do |participant|
              admitted_entry(participant, member_ids)
            end
          end
        end

        def admitted_entry(participant, member_ids)
          account = begin
            ActivityPub::TagManager.instance.uri_to_resource(participant[:identity], ::Account)
          rescue Addressable::URI::InvalidURIError
            nil
          end
          return if account.nil? || account.unavailable?
          return if account.local? && !member_ids.include?(account.id)
          return if !account.local? && DomainBlock.blocked?(account.domain)

          {
            'identity' => participant[:identity],
            'user_id' => account.id.to_s,
            'screen_sharing' => participant[:screen_sharing],
            'mic_muted' => participant[:mic_muted],
            'deafened' => participant[:deafened],
          }
        end
      end
    end
  end
end
