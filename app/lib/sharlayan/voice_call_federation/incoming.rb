# frozen_string_literal: true

module Sharlayan
  module VoiceCallFederation
    class Incoming
      ROOM_ID = %r{\A/chat/rooms/([a-zA-Z0-9]+)\z}
      TYPES = [STATE_TYPE, "cherrypick:#{STATE_TYPE}", "#{NAMESPACE}#{STATE_TYPE}"].freeze

      class << self
        def state?(json)
          object = json['object']
          object.is_a?(Hash) && TYPES.include?(object['type'])
        end

        def handle(json, account)
          return 'skip: remote voice calls disabled' unless Sharlayan::VoiceCallFederation.remote_join_enabled?
          return 'skip: suspended actor' if account.suspended?
          return 'skip: invalid actor' unless ActivityPub::TagManager.instance.uri_for(account) == value_id(json['actor'])

          parsed = parse(account.uri, json['object'])
          return "skip: #{parsed}" if parsed.is_a?(String)

          conversation = ChatConversation.find_by(uri: parsed[:room], owner_account_id: account.id)
          return 'skip: unknown room' if conversation.nil?

          "#{RemoteStates.store(conversation, parsed[:participants], parsed[:updated_at])}: voice state"
        end

        def parse(actor_uri, object)
          origin = Sharlayan::VoiceCallFederation.origin_of(actor_uri)
          room = object['room']
          return 'invalid voice state' unless object['id'].is_a?(String) && room.is_a?(String) && origin
          return 'voice state is not on the sender server' unless room.start_with?("#{origin}/") && ROOM_ID.match?(room.delete_prefix(origin))
          return 'voice state id does not belong to the room' unless object['id'] == Sharlayan::VoiceCallFederation.state_id(room)

          participants = RemoteStates.parse_participants(object['participants'], identity_key: 'id')
          return 'invalid participants' if participants.nil?

          updated_at = updated_millis(object['updated'])
          return 'invalid updated' if updated_at.nil?

          { room:, participants:, updated_at: }
        end

        private

        def value_id(value)
          value.is_a?(Hash) ? value['id'] : value
        end

        def updated_millis(value)
          return unless value.is_a?(String)

          time = Time.iso8601(value)
          (time.to_r * 1000).to_i
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
