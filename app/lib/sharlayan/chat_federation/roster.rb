# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    # Membership events reach a server in any order, and some never arrive. Events are ordered per room
    # and member by their `published` time, and the room owner's member list repairs what was lost.
    class Roster
      extend Redisable
      extend JsonLdHelper

      SYNC_INTERVAL = 60.seconds
      SYNC_SIGNERS = 3

      class << self
        # When both happen at the same time, the removal wins. Servers that do not send a time apply in arrival order.
        def applies?(conversation, account, published, removal: false)
          return true if published.nil?

          last = conversation.roster_states.find_by(account: account)&.last_roster_at
          last.nil? || published > last || (removal && published == last)
        end

        def advance(conversation, account, time)
          return if time.nil?

          state = conversation.roster_states.find_or_initialize_by(account: account)
          state.update!(last_roster_at: time) if state.last_roster_at.nil? || time > state.last_roster_at
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

        # A mirrored member may have been removed without this server hearing of it, and the owner would answer them with 404.
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
