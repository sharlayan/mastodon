# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Roster
      extend Redisable
      extend JsonLdHelper

      SYNC_INTERVAL = 60.seconds
      SYNC_SIGNERS = 3

      class << self
        def applies?(conversation, account, published, removal: false)
          return true if published.nil?

          last = conversation.roster_states.find_by(account: account)&.last_roster_at
          last.nil? || published > last || (removal && published == last)
        end

        def stale?(conversation, account, published)
          return false if published.nil?

          last = conversation.roster_states.find_by(account: account)&.last_roster_at
          last.present? && published < last
        end

        def advance(conversation, account, time)
          return if time.nil?

          state = conversation.roster_states.find_or_initialize_by(account: account)
          state.last_roster_at = time if time > state.last_roster_at
          state.save!
        end

        def member_departure_applies?(conversation, account, published)
          last = last_member_at(conversation, account)
          published.nil? || last.nil? || published >= last
        end

        def member_answer_stale?(conversation, account, published)
          last = last_member_at(conversation, account)
          published.present? && last.present? && published < last
        end

        def left_since?(conversation, account, published)
          last = last_member_at(conversation, account)
          published.present? && last.present? && published <= last
        end

        def record_member_time(conversation, account, time)
          return if time.nil?

          state = conversation.roster_states.find_or_initialize_by(account: account)
          state.last_member_at = time if state.last_member_at.nil? || time > state.last_member_at
          state.save!
        end

        def request_sync(conversation, subject)
          return unless Setting.chat_federation_enabled && conversation.chat_group? && !conversation.local?
          return unless redis.set("chat_roster_sync:#{conversation.id}:#{subject}", '1', nx: true, ex: SYNC_INTERVAL.to_i)

          ChatRosterSyncWorker.perform_async(conversation.id)
        end

        def sync(conversation)
          return unless Setting.chat_enabled && Setting.chat_federation_enabled && conversation.chat_group? && !conversation.local?

          group = fetch_group(conversation)
          return if group.nil? || group['attributedTo'] != conversation.owner_account&.uri

          members = group['_misskey_chatRoomMembers']
          roster_at = Incoming.time_of(group['_misskey_chatRoomRosterAt'])
          return unless members.is_a?(Array) && roster_at

          Sharlayan::ChatService.new.apply_roster(conversation, member_uris: members.grep(String), roster_at: roster_at)
        end

        private

        def last_member_at(conversation, account)
          conversation.roster_states.find_by(account: account)&.last_member_at
        end

        def fetch_group(conversation)
          conversation.accounts.local.limit(SYNC_SIGNERS).each do |signer|
            group = fetch_resource(conversation.uri, on_behalf_of: signer, raise_on_error: :temporary)
            return group if group.is_a?(Hash) && group['_misskey_chatRoomMembers'].present?
          end

          nil
        end
      end
    end
  end
end
