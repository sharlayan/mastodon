# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Payload
      CONTEXT = [
        'https://www.w3.org/ns/activitystreams',
        {
          'toot' => 'http://joinmastodon.org/ns#',
          'Emoji' => 'toot:Emoji',
          'misskey' => 'https://misskey-hub.net/ns#',
          '_misskey_talk' => 'misskey:_misskey_talk',
          '_misskey_content' => 'misskey:_misskey_content',
          '_misskey_reaction' => 'misskey:_misskey_reaction',
          '_misskey_chatRoom' => 'misskey:_misskey_chatRoom',
          '_misskey_chatArchived' => 'misskey:_misskey_chatArchived',
          '_misskey_chatRoomMembers' => 'misskey:_misskey_chatRoomMembers',
          '_misskey_chatRoomRosterAt' => 'misskey:_misskey_chatRoomRosterAt',
        },
      ].freeze

      class << self
        def create(message)
          {
            '@context' => CONTEXT,
            'id' => "#{message_uri(message)}/activity",
            'type' => 'Create',
            'actor' => actor_uri(message.account),
            'published' => message.created_at.iso8601,
            'to' => recipients(message),
            'object' => note(message).merge(legacy_room_fields(message)),
          }
        end

        def update(message)
          {
            '@context' => CONTEXT,
            'id' => "#{message_uri(message)}#update/#{message.edited_at&.to_i}-#{SecureRandom.hex(6)}",
            'type' => 'Update',
            'actor' => actor_uri(message.account),
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
            'object' => note(message).merge('updated' => (message.edited_at || Time.current).utc.iso8601(3)),
          }
        end

        def announce_message(message)
          relay_announce(message.chat_conversation, ERB::Util.url_encode(message_uri(message)), message_uri(message))
        end

        def announce_update(message)
          relay_announce(message.chat_conversation, "#{ERB::Util.url_encode(message_uri(message))}/#{message.edited_at.utc.strftime('%s%L')}", message_uri(message))
        end

        def announce_activity(conversation, activity)
          relay_announce(conversation, ERB::Util.url_encode(activity['id']), activity.except('@context', 'signature'))
        end

        # The time is taken before the members are read, so a change made while reading is not reported as older than it is.
        def roster(conversation)
          roster_at = Time.now.utc.iso8601(3)
          { '_misskey_chatRoomMembers' => conversation.accounts.map { |account| actor_uri(account) }, '_misskey_chatRoomRosterAt' => roster_at }
        end

        def delete(message)
          {
            '@context' => CONTEXT,
            'id' => "#{message_uri(message)}#delete",
            'type' => 'Delete',
            'actor' => actor_uri(message.account),
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
            'object' => {
              'id' => message_uri(message),
              'type' => 'Tombstone',
              'formerType' => 'Note',
            },
          }.merge(room_fields(message))
        end

        def reaction(message, account, reaction, reaction_id:)
          {
            '@context' => CONTEXT,
            'id' => reaction_uri(reaction_id),
            'type' => 'EmojiReact',
            'actor' => actor_uri(account),
            'object' => message_uri(message),
            'content' => reaction,
            '_misskey_reaction' => reaction,
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
          }.merge(reaction_tag(account, reaction)).merge(room_fields(message))
        end

        def undo_reaction(message, account, reaction, reaction_id:)
          react = reaction(message, account, reaction, reaction_id: reaction_id)
          {
            '@context' => CONTEXT,
            'id' => "#{react['id']}/undo",
            'type' => 'Undo',
            'actor' => actor_uri(account),
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
            'object' => react,
          }.merge(room_fields(message))
        end

        def invite(conversation, invitee)
          {
            '@context' => CONTEXT,
            'id' => "#{room_uri(conversation)}#invite/#{invitee.id}/#{SecureRandom.hex(6)}",
            'type' => 'Invite',
            'actor' => actor_uri(conversation.owner_account),
            'target' => actor_uri(invitee),
            'published' => Time.now.utc.iso8601(3),
            'object' => room(conversation),
          }
        end

        def accept(invitation)
          conversation = invitation.chat_conversation
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#accept/#{invitation.invitee_account_id}/#{SecureRandom.hex(6)}",
            'type' => 'Accept',
            'actor' => actor_uri(invitation.invitee_account),
            'published' => Time.now.utc.iso8601(3),
            'object' => invite_object(conversation, invitation),
          }
        end

        def reject(invitation)
          conversation = invitation.chat_conversation
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#reject/#{invitation.invitee_account_id}/#{SecureRandom.hex(6)}",
            'type' => 'Reject',
            'actor' => actor_uri(invitation.invitee_account),
            'published' => Time.now.utc.iso8601(3),
            'object' => invite_object(conversation, invitation),
          }
        end

        def reject_invite(owner, invitee, room)
          room_uri = room.is_a?(Hash) ? room['id'] : room
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{room_uri.to_s.split('/').last}#reject/#{invitee.id}",
            'type' => 'Reject',
            'actor' => actor_uri(invitee),
            'published' => Time.now.utc.iso8601(3),
            'object' => {
              'type' => 'Invite',
              'actor' => actor_uri(owner),
              'target' => actor_uri(invitee),
              'object' => room,
            },
          }
        end

        def cancel(invitation)
          conversation = invitation.chat_conversation
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#cancel/#{invitation.invitee_account_id}/#{SecureRandom.hex(6)}",
            'type' => 'Undo',
            'actor' => actor_uri(invitation.inviter_account),
            'published' => Time.now.utc.iso8601(3),
            'object' => invite_object(conversation, invitation),
          }
        end

        def add(conversation, account)
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#add/#{account.id}/#{SecureRandom.hex(6)}",
            'type' => 'Add',
            'actor' => actor_uri(conversation.owner_account),
            'target' => room_uri(conversation),
            'object' => actor_uri(account),
            'published' => Time.now.utc.iso8601(3),
          }
        end

        def remove(conversation, account, actor: account)
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#remove/#{account.id}/#{SecureRandom.hex(6)}",
            'type' => 'Remove',
            'actor' => actor_uri(actor),
            'target' => room_uri(conversation),
            'object' => actor_uri(account),
            'published' => Time.now.utc.iso8601(3),
          }
        end

        def update_room(conversation)
          {
            '@context' => CONTEXT,
            'id' => "#{room_uri(conversation)}#update/#{Time.now.to_i}/#{SecureRandom.hex(6)}",
            'type' => 'Update',
            'actor' => actor_uri(conversation.owner_account),
            'published' => Time.now.utc.iso8601,
            'object' => room(conversation),
          }
        end

        def delete_room(conversation)
          {
            '@context' => CONTEXT,
            'id' => "#{room_uri(conversation)}#delete",
            'type' => 'Delete',
            'actor' => actor_uri(conversation.owner_account),
            'published' => Time.now.utc.iso8601,
            'object' => {
              'id' => room_uri(conversation),
              'type' => 'Tombstone',
              'formerType' => 'Group',
            },
          }
        end

        def note(message, domain: nil)
          text = message.text.to_s
          result = {
            'id' => message_uri(message),
            'type' => 'Note',
            'attributedTo' => actor_uri(message.account),
            'content' => ERB::Util.html_escape(text),
            '_misskey_content' => text,
            'source' => { 'content' => text, 'mediaType' => 'text/x.misskeymarkdown' },
            'to' => recipients(message),
            'published' => message.created_at.iso8601,
            '_misskey_talk' => true,
          }
          if message.chat_conversation.chat_group?
            result['context'] = room_uri(message.chat_conversation)
            result['_misskey_chatRoom'] = result['context']
          end
          result['updated'] = message.edited_at.utc.iso8601(3) if message.edited_at.present?
          result['inReplyTo'] = message_uri(message.reply_to) if message.reply_to.present?
          result['attachment'] = documents(message, domain) if message.media_attachments.any?
          result
        end

        # An attachment address belongs to one server, so each server gets a copy of the activity with its own.
        def for_domain(payload, message, domain)
          payload.merge('object' => payload['object'].merge('attachment' => documents(message, domain)))
        end

        def room(conversation)
          {
            'id' => room_uri(conversation),
            'type' => 'Group',
            'name' => conversation.title,
            'summary' => conversation.description.to_s,
            'attributedTo' => actor_uri(conversation.owner_account),
            '_misskey_chatArchived' => conversation.archived?,
            'updated' => (conversation.state_updated_at || conversation.updated_at).utc.iso8601(3),
          }
        end

        def message_uri(message)
          message.uri.presence || "#{base_url}/chat/messages/#{message.id}"
        end

        def room_uri(conversation)
          conversation.uri.presence || "#{base_url}/chat/rooms/#{conversation.id}"
        end

        def actor_uri(account)
          ActivityPub::TagManager.instance.uri_for(account)
        end

        def recipients(message)
          message.chat_conversation.accounts.where.not(id: message.account_id).map { |account| actor_uri(account) }
        end

        private

        def relay_announce(conversation, relay_id, object)
          room = room_uri(conversation)
          {
            '@context' => CONTEXT,
            'id' => "#{room}#relay/#{relay_id}",
            'type' => 'Announce',
            'actor' => actor_uri(conversation.owner_account),
            'object' => object,
            'context' => room,
            '_misskey_chatRoom' => room,
            'published' => Time.now.utc.iso8601,
            'to' => conversation.accounts.where.not(id: conversation.owner_account_id).map { |account| actor_uri(account) },
          }
        end

        # Servers from before `context` and `_misskey_chatRoom` read the room only from @context, and
        # take a Note with one address for a direct message, so the sender is addressed like they do.
        # A fetched Note goes without these, because there it would have to replace the real @context.
        def legacy_room_fields(message)
          return {} unless message.chat_conversation.chat_group?

          { '@context' => room_uri(message.chat_conversation), 'to' => [actor_uri(message.account), *recipients(message)] }
        end

        # Lets a server tell that the room is gone when it has never seen the message. It proves nothing else.
        def room_fields(message)
          return {} unless message.chat_conversation.chat_group?

          room = room_uri(message.chat_conversation)
          { 'context' => room, '_misskey_chatRoom' => room }
        end

        def reaction_tag(account, reaction)
          shortcode = ChatMessageReaction.shortcode_of(reaction)
          emoji = shortcode && CustomEmoji.find_by(shortcode: shortcode, domain: account.domain, disabled: false, local_only: false)
          return {} if emoji.nil?

          { 'tag' => [ActivityPub::EmojiSerializer.new(emoji).serializable_hash.as_json] }
        end

        def reaction_uri(reaction_id)
          "#{base_url}/chat/reactions/#{reaction_id}"
        end

        def invite_object(conversation, invitation)
          {
            'type' => 'Invite',
            'actor' => actor_uri(conversation.owner_account),
            'target' => actor_uri(invitation.invitee_account),
            'object' => room(conversation),
          }
        end

        def documents(message, domain)
          message.media_attachments.map { |attachment| document(attachment, domain) }
        end

        def document(attachment, domain)
          url = "#{base_url}/media_proxy/#{attachment.id}/original"
          url += "?token=#{ERB::Util.url_encode(Sharlayan::ChatFederation::MediaToken.generate(attachment, domain: domain))}" if domain.present?

          {
            'type' => 'Document',
            'mediaType' => attachment.file_content_type,
            'url' => url,
            'name' => attachment.description,
            'sensitive' => false,
          }
        end

        def base_url
          "#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.web_domain}"
        end
      end
    end
  end
end
