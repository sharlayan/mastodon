# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Payload
      CONTEXT = [
        'https://www.w3.org/ns/activitystreams',
        {
          'misskey' => 'https://misskey-hub.net/ns#',
          '_misskey_talk' => 'misskey:_misskey_talk',
          '_misskey_content' => 'misskey:_misskey_content',
          '_misskey_reaction' => 'misskey:_misskey_reaction',
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
            'object' => note(message),
          }
        end

        def update(message)
          {
            '@context' => CONTEXT,
            'id' => "#{message_uri(message)}#update/#{message.edited_at&.to_i}",
            'type' => 'Update',
            'actor' => actor_uri(message.account),
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
            'object' => note(message).merge('updated' => (message.edited_at || Time.current).utc.iso8601),
          }
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
          }
        end

        def reaction(message, account, reaction)
          {
            '@context' => CONTEXT,
            'id' => reaction_uri(message, account, reaction),
            'type' => 'EmojiReact',
            'actor' => actor_uri(account),
            'object' => message_uri(message),
            'content' => reaction,
            '_misskey_reaction' => reaction,
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
          }
        end

        def undo_reaction(message, account, reaction)
          react = reaction(message, account, reaction)
          {
            '@context' => CONTEXT,
            'id' => "#{react['id']}/undo",
            'type' => 'Undo',
            'actor' => actor_uri(account),
            'published' => Time.now.utc.iso8601,
            'to' => recipients(message),
            'object' => react,
          }
        end

        def invite(conversation, invitee)
          {
            '@context' => CONTEXT,
            'id' => "#{room_uri(conversation)}#invite/#{invitee.id}",
            'type' => 'Invite',
            'actor' => actor_uri(conversation.owner_account),
            'target' => actor_uri(invitee),
            'published' => Time.now.utc.iso8601,
            'object' => room(conversation),
          }
        end

        def accept(invitation)
          conversation = invitation.chat_conversation
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#accept/#{invitation.invitee_account_id}",
            'type' => 'Accept',
            'actor' => actor_uri(invitation.invitee_account),
            'published' => Time.now.utc.iso8601,
            'object' => invite_object(conversation, invitation),
          }
        end

        def reject(invitation)
          conversation = invitation.chat_conversation
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#reject/#{invitation.invitee_account_id}",
            'type' => 'Reject',
            'actor' => actor_uri(invitation.invitee_account),
            'published' => Time.now.utc.iso8601,
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
            'published' => Time.now.utc.iso8601,
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
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#cancel/#{invitation.invitee_account_id}",
            'type' => 'Undo',
            'actor' => actor_uri(invitation.inviter_account),
            'published' => Time.now.utc.iso8601,
            'object' => invite_object(conversation, invitation),
          }
        end

        def add(conversation, account)
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#add/#{account.id}",
            'type' => 'Add',
            'actor' => actor_uri(conversation.owner_account),
            'target' => room_uri(conversation),
            'object' => actor_uri(account),
            'published' => Time.now.utc.iso8601,
          }
        end

        def remove(conversation, account)
          {
            '@context' => CONTEXT,
            'id' => "#{base_url}/chat/rooms/#{conversation.id}#remove/#{account.id}",
            'type' => 'Remove',
            'actor' => actor_uri(account),
            'target' => room_uri(conversation),
            'object' => actor_uri(account),
            'published' => Time.now.utc.iso8601,
          }
        end

        def update_room(conversation)
          {
            '@context' => CONTEXT,
            'id' => "#{room_uri(conversation)}#update/#{Time.now.to_i}",
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

        def note(message)
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
          result['@context'] = room_uri(message.chat_conversation) if message.chat_conversation.chat_group?
          result['attachment'] = [document(message.media_attachments.first)] if message.media_attachments.any?
          result
        end

        def room(conversation)
          {
            'id' => room_uri(conversation),
            'type' => 'Group',
            'name' => conversation.title,
            'summary' => conversation.description.to_s,
            'attributedTo' => actor_uri(conversation.owner_account),
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

        def reaction_uri(message, account, reaction)
          "#{base_url}/chat/reactions/#{message.id}/#{account.id}/#{ERB::Util.url_encode(reaction)}"
        end

        def invite_object(conversation, invitation)
          {
            'type' => 'Invite',
            'actor' => actor_uri(conversation.owner_account),
            'target' => actor_uri(invitation.invitee_account),
            'object' => room(conversation),
          }
        end

        def document(attachment)
          url = attachment.file&.url
          url = "#{base_url}#{url}" if url&.start_with?('/')

          {
            'type' => 'Document',
            'mediaType' => attachment.file_content_type,
            'url' => url,
            'name' => attachment.description,
            'sensitive' => false,
          }
        end

        def base_url
          "#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.local_domain}"
        end
      end
    end
  end
end
