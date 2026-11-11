# frozen_string_literal: true

module Sharlayan
  module VoiceCallFederation
    class Outgoing
      extend Redisable

      MIN_INTERVAL = 10.seconds
      RESEND_INTERVAL = 240.seconds
      STAMP_TTL = 1.hour

      STAMP_SCRIPT = <<~LUA
        local last = tonumber(redis.call('GET', KEYS[1]) or '0')
        local now = tonumber(ARGV[1])
        local stamp = now > last and now or last + 1
        redis.call('SET', KEYS[1], stamp, 'EX', ARGV[2])
        return stamp
      LUA

      class << self
        def stamp(conversation_id)
          redis.eval(STAMP_SCRIPT, keys: ["voice_call:federation:stamp:#{conversation_id}"], argv: [(Time.now.to_f * 1000).to_i, STAMP_TTL.to_i]).to_i
        end

        def schedule(conversation)
          return unless conversation&.local? && Sharlayan::VoiceCallFederation.host_enabled? && remote_members?(conversation)

          VoiceCallFederationWorker.perform_async(conversation.id)
        end

        def publish(conversation)
          return unless conversation.local? && Sharlayan::VoiceCallFederation.host_enabled?

          allocation = VoiceCallAllocation.find_by(chat_conversation_id: conversation.id)
          participants = allocation&.active? ? allocation.participants : []
          entries = Sharlayan::VoiceCallFederation.participant_entries(participants).sort_by { |entry| entry['id'] }
          digest = Digest::SHA256.hexdigest(entries.to_json)
          last = last_record(conversation.id)
          return if last && last['digest'] == digest && (entries.empty? || Time.now.to_i - last['at'].to_i < RESEND_INTERVAL)
          return if entries.any? && !open_gate(conversation.id)

          deliver(conversation, entries, stamp(conversation.id))
          redis.set(record_key(conversation.id), { digest:, at: Time.now.to_i }.to_json, ex: (RESEND_INTERVAL * 2).to_i)
        end

        def payload(conversation, entries, updated_at)
          room_uri = Sharlayan::ChatFederation::Payload.room_uri(conversation)
          {
            '@context' => Sharlayan::VoiceCallFederation::CONTEXT,
            'id' => "#{Sharlayan::VoiceCallFederation.state_id(room_uri)}#update/#{updated_at}",
            'type' => 'Update',
            'actor' => ActivityPub::TagManager.instance.uri_for(conversation.owner_account),
            'published' => Time.at(updated_at / 1000.0).utc.iso8601(3),
            'object' => {
              'id' => Sharlayan::VoiceCallFederation.state_id(room_uri),
              'type' => Sharlayan::VoiceCallFederation::STATE_TYPE,
              'room' => room_uri,
              'participants' => entries,
              'updated' => Time.at(updated_at / 1000.0).utc.iso8601(3),
            },
          }
        end

        private

        def deliver(conversation, entries, updated_at)
          Sharlayan::ChatFederation::Delivery.call(actor: conversation.owner_account, conversation:, payload: payload(conversation, entries, updated_at))
        end

        def remote_members?(conversation)
          conversation.memberships.joins(:account).merge(::Account.remote).exists?
        end

        def open_gate(conversation_id)
          key = "voice_call:federation:gate:#{conversation_id}"
          return true if redis.set(key, '1', px: MIN_INTERVAL.in_milliseconds.to_i, nx: true)

          wait = redis.pttl(key)
          VoiceCallFederationWorker.perform_in(((wait.positive? ? wait : MIN_INTERVAL.in_milliseconds) / 1000.0) + 0.1, conversation_id)
          false
        end

        def last_record(conversation_id)
          raw = redis.get(record_key(conversation_id))
          raw && JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end

        def record_key(conversation_id)
          "voice_call:federation:sent:#{conversation_id}"
        end
      end
    end
  end
end
