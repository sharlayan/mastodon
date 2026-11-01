# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Incoming
      class << self
        def chat_create?(json)
          object = json['object']
          object.is_a?(Hash) &&
            equals_type?(object['type'], 'Note') &&
            object['_misskey_talk'] == true &&
            object['id'].present?
        end

        def chat_update?(json)
          chat_create?(json) || (json['object'].is_a?(Hash) &&
            equals_type?(json['object']['type'], 'Note') &&
            json['object']['_misskey_talk'] == true)
        end

        def chat_delete?(json)
          object = json['object']
          uri = uri_of(object)
          uri.present? && (chat_message_uri?(uri) || room_uri?(uri) || ChatMessage.exists?(uri: uri))
        end

        def chat_reaction?(json)
          message = ChatMessage.find_by(uri: uri_of(json['object']))
          message.present?
        end

        def chat_undo_reaction?(json)
          object = json['object']
          object.is_a?(Hash) && equals_type?(object['type'], 'EmojiReact') && chat_reaction?(object)
        end

        def chat_invite?(json)
          object = json['object']
          object.is_a?(Hash) && equals_type?(object['type'], 'Invite')
        end

        def chat_invite_activity?(json)
          equals_type?(json['type'], 'Invite')
        end

        def chat_room?(json)
          object = json['object']
          object.is_a?(Hash) && equals_type?(object['type'], 'Group') && room_uri?(uri_of(object))
        end

        def chat_add?(json)
          room_uri?(uri_of(json['target']))
        end

        def handle_create(json, account, **options)
          object = json['object']
          return 'skip: not a chat note' unless chat_create?(json)
          return 'skip: actor mismatch' unless authored_by?(object, account)

          uri = object['id']
          return 'skip: deleted before create' if service.tombstone?(uri)

          text = text_of(object)
          attachment = attachment_of(object)
          return 'skip: empty chat message' if text.blank? && attachment.nil?

          local_recipient = local_recipient_for(json, object, options[:delivered_to_account_id])
          return 'skip: no local recipient' if local_recipient.nil?

          room_uri = room_uri_of(object)
          if room_uri.present?
            service.receive_group_message(
              account,
              room_uri: room_uri,
              uri: uri,
              text: text,
              created_at: time_of(object['published']),
              attachment: attachment
            )
          else
            service.receive_direct_message(
              local_recipient,
              account,
              uri: uri,
              text: text,
              created_at: time_of(object['published']),
              attachment: attachment
            )
          end
          'ok: chat message created'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped incoming chat message from #{account.uri}: #{e.message}")
          'skip: chat policy'
        end

        def handle_update(json, account, **options)
          object = json['object']
          return 'skip: not a chat note' unless chat_update?(json)
          return 'skip: actor mismatch' unless authored_by?(object, account)

          message = ChatMessage.find_by(uri: object['id'])
          return handle_create(json, account, **options) if message.nil?

          text = text_of(object)
          return 'skip: empty chat message' if text.blank?

          service.update_remote_message(account, message, text: text, edited_at: time_of(object['updated']) || Time.current)
          'ok: chat message updated'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped incoming chat update from #{account.uri}: #{e.message}")
          'skip: chat update'
        end

        def handle_delete(json, account)
          object = json['object']
          uri = uri_of(object)
          return false if uri.blank?

          if room_uri?(uri)
            service.receive_room_delete(account, room_uri: uri)
            return 'ok: chat room deleted'
          end

          message = ChatMessage.find_by(uri: uri)
          if message.present?
            service.delete_remote_message(account, message)
            return 'ok: chat message deleted'
          end

          return false unless chat_message_uri?(uri)

          service.remember_tombstone(uri)
          'ok: chat message tombstone stored'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped incoming chat delete from #{account.uri}: #{e.message}")
          'skip: chat delete'
        end

        def handle_reaction(json, account)
          message = ChatMessage.find_by(uri: uri_of(json['object']))
          return false if message.nil?

          reaction = json['_misskey_reaction'] || json['content']
          return 'skip: empty reaction' if reaction.blank?

          service.react_remote(account, message, reaction.to_s)
          'ok: chat reaction'
        rescue ActiveRecord::RecordInvalid, Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped incoming chat reaction from #{account.uri}: #{e.message}")
          'skip: chat reaction'
        end

        def handle_undo_reaction(json, account)
          object = json['object']
          return false unless chat_undo_reaction?(json)

          message = ChatMessage.find_by(uri: uri_of(object['object']))
          return false if message.nil?

          reaction = object['_misskey_reaction'] || object['content']
          return 'skip: empty reaction' if reaction.blank?

          service.unreact_remote(account, message, reaction.to_s)
          'ok: chat reaction undone'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped incoming chat reaction undo from #{account.uri}: #{e.message}")
          'skip: chat reaction undo'
        end

        def handle_invite(json, account)
          return false unless chat_invite_activity?(json)

          room = json['object']
          room_uri = uri_of(room)
          return 'skip: invalid chat room' if room_uri.blank?
          return 'skip: invalid target' unless uri_of(json['target']) == local_target_uri?(json, account)

          invitee = local_account_for_target(json)
          return 'skip: no local invitee' if invitee.nil?

          begin
            conversation = service.receive_invite(
              invitee,
              account,
              room_uri: room_uri,
              title: room['name'],
              description: room['summary']
            )
            broadcast_invitation(conversation, invitee)
            'ok: chat invitation received'
          rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
            Rails.logger.info("Rejected chat invitation from #{account.uri}: #{e.message}")
            reject_invite(account, invitee, room)
            'ok: chat invitation rejected'
          end
        end

        def handle_accept(json, account)
          return false unless chat_invite?(json)

          room_uri = uri_of(json['object']['object'])
          return 'skip: invalid chat room' if room_uri.blank?

          service.receive_accept(account, room_uri: room_uri)
          'ok: chat invitation accepted'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped chat accept from #{account.uri}: #{e.message}")
          'skip: chat accept'
        end

        def handle_reject(json, account)
          return false unless chat_invite?(json)

          room_uri = uri_of(json['object']['object'])
          return 'skip: invalid chat room' if room_uri.blank?

          service.receive_reject(account, room_uri: room_uri)
          'ok: chat invitation rejected'
        end

        def handle_add(json, account)
          return false unless chat_add?(json)

          service.receive_add(account, room_uri: uri_of(json['target']), account_uri: uri_of(json['object']))
          'ok: chat room member added'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped chat Add from #{account.uri}: #{e.message}")
          'skip: chat add'
        end

        def handle_remove(json, account)
          return false unless chat_add?(json)

          service.receive_remove(account, room_uri: uri_of(json['target']), account_uri: uri_of(json['object']))
          'ok: chat room member removed'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped chat Remove from #{account.uri}: #{e.message}")
          'skip: chat remove'
        end

        def handle_room_update(json, account)
          return false unless chat_room?(json)

          object = json['object']
          service.receive_room_update(account, room_uri: uri_of(object), title: object['name'], description: object['summary'])
          'ok: chat room updated'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped chat room update from #{account.uri}: #{e.message}")
          'skip: chat room update'
        end

        private

        def service
          @service ||= Sharlayan::ChatService.new
        end

        def equals_type?(value, type)
          value == type || (value.is_a?(Array) && value.include?(type))
        end

        def uri_of(value)
          return value if value.is_a?(String)
          return value['id'] if value.is_a?(Hash)

          nil
        end

        def chat_message_uri?(uri)
          uri.include?('/chat/messages/')
        end

        def room_uri?(uri)
          uri.present? && uri.include?('/chat/rooms/')
        end

        def room_uri_of(object)
          context = object['@context']
          context = context.find { |value| value.is_a?(String) && value.include?('/chat/rooms/') } if context.is_a?(Array)
          return context if context.is_a?(String) && room_uri?(context)

          nil
        end

        def authored_by?(object, account)
          attributed_to = uri_of(object['attributedTo'])
          attributed_to == account.uri && same_host?(object['id'], account.uri)
        end

        def same_host?(first, second)
          first.present? && second.present? &&
            Addressable::URI.parse(first).host == Addressable::URI.parse(second).host
        rescue Addressable::URI::InvalidURIError
          false
        end

        def text_of(object)
          source = object['source']
          return source['content'] if source.is_a?(Hash) && source['mediaType'] == 'text/x.misskeymarkdown' && source['content'].is_a?(String)
          return object['_misskey_content'] if object['_misskey_content'].is_a?(String)
          return if object['content'].blank?

          CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(object['content'].to_s))
        end

        def attachment_of(object)
          attachment = object['attachment']
          attachment = attachment.first if attachment.is_a?(Array)
          attachment.is_a?(Hash) ? attachment : nil
        end

        def time_of(value)
          return if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def local_recipient_for(json, object, delivered_to_account_id)
          if delivered_to_account_id.present?
            account = ::Account.local.find_by(id: delivered_to_account_id)
            return account if account.present?
          end

          recipients(object).find(&:local?)
        end

        def recipients(object)
          values = object['to']
          values = [values] unless values.is_a?(Array)
          values.filter_map do |value|
            ::Account.find_by(uri: uri_of(value))
          end
        end

        def local_target_uri?(json, _account)
          local_account_for_target(json)&.then { |account| ActivityPub::TagManager.instance.uri_for(account) }
        end

        def local_account_for_target(json)
          target = uri_of(json['target'])
          account = ActivityPub::TagManager.instance.uri_to_resource(target, ::Account)
          account if account&.local?
        end

        def broadcast_invitation(conversation, invitee)
          invitation = conversation.invitations.pending.find_by(invitee_account: invitee)
          return if invitation.nil?

          payload = REST::ChatInvitationSerializer.new(invitation, current_account: invitee).as_json
          RedisConnection.with do |redis|
            redis.publish("timeline:#{invitee.id}", JSON.generate(event: 'chat.invitation', payload: JSON.generate(payload)))
          end
        end

        def reject_invite(account, invitee, room)
          payload = Sharlayan::ChatFederation::Payload.reject_invite(account, invitee, room)
          return if account.inbox_url.blank?

          ActivityPub::DeliveryWorker.perform_async(payload.to_json, invitee.id, account.inbox_url)
        end
      end
    end
  end
end