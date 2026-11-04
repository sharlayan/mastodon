# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class Incoming
      extend Redisable
      extend JsonLdHelper

      ROOM_URI = %r{/chat/rooms/[a-zA-Z0-9]+\z}
      MESSAGE_URI = %r{/chat/messages/[a-zA-Z0-9_-]+\z}
      REACTION_TYPES = %w(EmojiReact Like).freeze

      class << self
        def chat_create?(json)
          object = json['object']
          object.is_a?(Hash) &&
            equals_type?(object['type'], 'Note') &&
            object['_misskey_talk'] == true &&
            object['id'].present?
        end

        def chat_update?(json)
          object = json['object']
          return false unless object.is_a?(Hash) && equals_type?(object['type'], 'Note')

          object['_misskey_talk'] == true || (uri_of(object).present? && ChatMessage.exists?(uri: uri_of(object)))
        end

        def chat_delete?(json)
          uri = uri_of(json['object'])
          uri.present? && (room_uri?(uri) || chat_message?(uri))
        end

        def chat_reaction?(json)
          chat_message?(uri_of(json['object']))
        end

        def chat_undo_reaction?(json)
          object = json['object']
          object.is_a?(Hash) && REACTION_TYPES.any? { |type| equals_type?(object['type'], type) } && chat_reaction?(object)
        end

        def chat_announce?(json)
          object = json['object']
          room_uri_of(json).present? || (object.is_a?(Hash) && object['_misskey_talk'] == true) || chat_message?(uri_of(object))
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
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          object = json['object']
          return 'skip: not a chat note' unless chat_create?(json)
          return 'skip: suspended actor' if account.suspended?
          return 'skip: actor mismatch' unless authored_by?(object, account)
          return 'skip: unsupported chat room context' if room_uri_of(object).nil? && Array.wrap(object['@context']).any? { |value| room_uri?(value) }

          uri = uri_of(object)
          return 'skip: invalid chat message id' if uri.blank?
          return 'skip: deleted before create' if deleted_before_create?(uri, account)

          text = text_of(object)
          attachments = attachments_of(object)
          return 'skip: empty chat message' if text.blank? && attachments.empty?

          room_uri = room_uri_of(object)
          if room_uri.present?
            service.receive_group_message(account, room_uri: room_uri, uri: uri, **message_attributes(object, text, attachments))
          else
            local_recipient = local_recipient_for(object, options[:delivered_to_account_id])
            return 'skip: no local recipient' if local_recipient.nil?

            service.receive_direct_message(local_recipient, account, uri: uri, **message_attributes(object, text, attachments))
          end
          'ok: chat message created'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped incoming chat message from #{account.uri}: #{e.message}")
          'skip: chat policy'
        end

        def handle_announce(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          uri = uri_of(json['object'])
          room_uri = room_uri_of(json)
          return 'skip: not a relayed chat message' if uri.blank? || room_uri.blank?

          conversation = ChatConversation.find_by(uri: room_uri)
          if conversation.nil?
            raise DependencyNotReadyError, 'Waiting for chat room' if same_host?(room_uri, account.uri)

            return 'skip: unknown chat room'
          end
          return 'skip: not the room owner' unless conversation.owner_account_id == account.id
          return 'ok: chat message already received' if ChatMessage.exists?(uri: uri)
          return 'skip: local chat message' if ActivityPub::TagManager.instance.local_uri?(uri)

          signer = conversation.accounts.local.first
          if signer.nil?
            raise DependencyNotReadyError, 'Waiting for chat membership' if conversation.invitations.pending.joins(:invitee_account).merge(::Account.local).exists?

            return 'skip: no local member'
          end

          note = fetch_relayed_note(uri, signer)
          return 'skip: chat message deleted' if note == :deleted
          return 'skip: invalid chat message' unless note && chat_create?('object' => note) && room_uri_of(note) == room_uri

          author = service.resolve_account(uri_of(note['attributedTo']))
          raise DependencyNotReadyError, 'Waiting for chat message author' if author.nil?
          return 'skip: invalid chat message author' unless author.remote? && !author.suspended? && authored_by?(note, author)
          return 'skip: deleted before create' if deleted_before_create?(uri, author)

          text = text_of(note)
          attachments = attachments_of(note)
          return 'skip: empty chat message' if text.blank? && attachments.empty?

          service.receive_group_message(author, room_uri: room_uri, uri: uri, **message_attributes(note, text, attachments))
          'ok: relayed chat message created'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped relayed chat message from #{account.uri}: #{e.message}")
          'skip: relayed chat message'
        end

        def handle_update(json, account, **)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          object = json['object']
          return 'skip: not a chat note' unless chat_update?(json)
          return 'skip: actor mismatch' unless authored_by?(object, account)

          message = ChatMessage.find_by(uri: object['id'])
          return handle_create(json, account, **) if message.nil?

          text = text_of(object)
          return 'skip: empty chat message' if text.blank? && message.media_attachments.empty?

          service.update_remote_message(account, message, text: text, edited_at: time_of(object['updated']) || Time.current)
          'ok: chat message updated'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped incoming chat update from #{account.uri}: #{e.message}")
          'skip: chat update'
        end

        def handle_delete(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          object = json['object']
          uri = uri_of(object)
          return false if uri.blank?

          if room_uri?(uri)
            service.receive_room_delete(account, room_uri: uri)
            service.remember_room_tombstone(uri, account)
            return 'ok: chat room deleted'
          end

          message = ChatMessage.find_by(uri: uri)
          if message.present?
            service.delete_remote_message(account, message)
            return 'ok: chat message deleted'
          end

          return false unless chat_message_uri?(uri)

          service.remember_tombstone(uri, account)
          'ok: chat message tombstone stored'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped incoming chat delete from #{account.uri}: #{e.message}")
          'skip: chat delete'
        end

        def handle_reaction(json, account, &emoji_importer)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          uri = uri_of(json['object'])
          return false if uri.blank?

          reaction = json['_misskey_reaction'] || json['content']
          return 'skip: empty reaction' if reaction.blank?

          activity_id = reaction_activity_id(json, account)
          message = ChatMessage.find_by(uri: uri)
          raise DependencyNotReadyError, 'Chat message has not arrived' if message.nil?

          service.react_remote(account, message, reaction.to_s, activity_id: activity_id, &emoji_importer)
          'ok: chat reaction'
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error => e
          Rails.logger.info("Dropped incoming chat reaction from #{account.uri}: #{e.message}")
          'skip: chat reaction'
        end

        def handle_undo_reaction(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          object = json['object']
          return false unless chat_undo_reaction?(json)
          return 'skip: actor mismatch' if object['actor'].present? && uri_of(object['actor']) != account.uri

          reaction = object['_misskey_reaction'] || object['content']
          return 'skip: empty reaction' if reaction.blank?

          activity_id = reaction_activity_id(object, account)
          message = ChatMessage.find_by(uri: uri_of(object['object']))
          raise DependencyNotReadyError, 'Chat message has not arrived' if message.nil?

          service.unreact_remote(account, message, reaction.to_s, activity_id: activity_id)
          'ok: chat reaction undone'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped incoming chat reaction undo from #{account.uri}: #{e.message}")
          'skip: chat reaction undo'
        end

        def handle_invite(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          return false unless chat_invite_activity?(json)

          room = json['object']
          room_uri = uri_of(room)
          return 'skip: invalid chat room' unless chat_room?(json) && authored_by?(room, account)
          return 'skip: deleted before invite' if service.room_tombstoned?(room_uri, account)

          invitee = local_account_for_target(json)
          return 'skip: no local invitee' if invitee.nil?
          return 'skip: cancelled before invite' if service.invite_cancelled?(room_uri, account, invitee, time_of(json['published']))

          begin
            service.receive_invite(
              invitee,
              account,
              room_uri: room_uri,
              title: room['name'],
              description: room['summary'],
              archived: room['_misskey_chatArchived'],
              updated: time_of(room['updated'])
            )
            'ok: chat invitation received'
          rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
            Rails.logger.info("Rejected chat invitation from #{account.uri}: #{e.message}")
            reject_invite(account, invitee, room)
            'ok: chat invitation rejected'
          end
        end

        def handle_undo_invite(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled
          return false unless chat_invite?(json)

          invitation = json['object']
          return 'skip: actor mismatch' unless uri_of(invitation['actor']) == account.uri

          invitee = local_account_for_target(invitation)
          return 'skip: no local invitee' if invitee.nil?

          service.receive_cancel(account, room_uri: uri_of(invitation['object']), invitee: invitee, published: time_of(json['published']))
          'ok: chat invitation cancelled'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped chat Undo Invite from #{account.uri}: #{e.message}")
          'skip: chat invitation cancellation'
        end

        def handle_accept(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          return false unless chat_invite?(json)

          room_uri = uri_of(json['object']['object'])
          return 'skip: invalid chat room' if room_uri.blank?

          service.receive_accept(account, room_uri: room_uri)
          'ok: chat invitation accepted'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped chat accept from #{account.uri}: #{e.message}")
          service.refuse_accept(account, room_uri: room_uri)
          'skip: chat accept'
        end

        def handle_reject(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          return false unless chat_invite?(json)

          room_uri = uri_of(json['object']['object'])
          return 'skip: invalid chat room' if room_uri.blank?

          service.receive_reject(account, room_uri: room_uri)
          'ok: chat invitation rejected'
        end

        def handle_add(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          return false unless chat_add?(json)

          service.receive_add(account, room_uri: uri_of(json['target']), account_uri: uri_of(json['object']))
          'ok: chat room member added'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped chat Add from #{account.uri}: #{e.message}")
          'skip: chat add'
        end

        def handle_remove(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          return false unless chat_add?(json)

          service.receive_remove(account, room_uri: uri_of(json['target']), account_uri: uri_of(json['object']))
          'ok: chat room member removed'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped chat Remove from #{account.uri}: #{e.message}")
          'skip: chat remove'
        end

        def handle_room_update(json, account)
          return 'skip: chat federation disabled' unless Setting.chat_enabled && Setting.chat_federation_enabled

          return false unless chat_room?(json)

          object = json['object']
          service.receive_room_update(account, room_uri: uri_of(object), title: object['name'], description: object['summary'], archived: object['_misskey_chatArchived'], updated: time_of(object['updated']))
          'ok: chat room updated'
        rescue Sharlayan::ChatService::Forbidden, Sharlayan::ChatService::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          Rails.logger.info("Dropped chat room update from #{account.uri}: #{e.message}")
          'skip: chat room update'
        end

        private

        def reaction_activity_id(json, account)
          id = json['id']
          return if id.nil?

          raise Sharlayan::ChatService::Error, 'Invalid reaction activity ID' unless id.is_a?(String) && id.length <= 2048 && same_host?(id, account.uri) && %w(http https).include?(Addressable::URI.parse(id).scheme)

          id
        end

        def service
          @service ||= Sharlayan::ChatService.new
        end

        def equals_type?(value, type)
          value == type || (value.is_a?(Array) && value.include?(type))
        end

        def uri_of(value)
          return value if value.is_a?(String)
          return value['id'] if value.is_a?(Hash) && value['id'].is_a?(String)

          nil
        end

        def chat_message_uri?(uri)
          uri.is_a?(String) && MESSAGE_URI.match?(uri)
        end

        def chat_message?(uri)
          return false if uri.blank?

          ChatMessage.exists?(uri: uri) || (chat_message_uri?(uri) && !::Status.exists?(uri: uri))
        end

        def room_uri?(uri)
          uri.is_a?(String) && ROOM_URI.match?(uri)
        end

        def room_uri_of(object)
          [object['_misskey_chatRoom'], object['context']].find { |value| room_uri?(value) }
        end

        def message_attributes(object, text, attachments)
          {
            text: text,
            created_at: time_of(object['published']),
            edited_at: time_of(object['updated']),
            attachments: attachments,
            reply_to_uri: uri_of(object['inReplyTo']),
          }
        end

        def fetch_relayed_note(uri, signer)
          note = fetch_resource(uri, on_behalf_of: signer, raise_on_error: :all)
          equals_type?(note&.fetch('type', nil), 'Tombstone') ? :deleted : note
        rescue Mastodon::UnexpectedResponseError => e
          return :deleted if e.response.code == 410
          raise DependencyNotReadyError, 'Waiting for chat message' if e.response.code == 404

          raise
        end

        def authored_by?(object, account)
          attributed_to = uri_of(object['attributedTo'])
          attributed_to == account.uri && same_host?(object['id'], account.uri)
        end

        def same_host?(first, second)
          first.is_a?(String) && second.is_a?(String) && first.present? && second.present? &&
            Addressable::URI.parse(first).host == Addressable::URI.parse(second).host
        rescue Addressable::URI::InvalidURIError
          false
        end

        def deleted_before_create?(uri, account)
          service.tombstone?(uri, account) ||
            redis.exists?("delete_upon_arrival:#{account.id}:#{uri}") ||
            Tombstone.exists?(uri: uri)
        end

        def text_of(object)
          source = object['source']
          return source['content'] if source.is_a?(Hash) && source['mediaType'] == 'text/x.misskeymarkdown' && source['content'].is_a?(String)
          return object['_misskey_content'] if object['_misskey_content'].is_a?(String)
          return if object['content'].blank?

          CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(object['content'].to_s))
        end

        def attachments_of(object)
          Array.wrap(object['attachment']).grep(Hash).first(Setting.chat_max_attachments)
        end

        def time_of(value)
          return if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def local_recipient_for(object, delivered_to_account_id)
          if delivered_to_account_id.present?
            account = ::Account.local.find_by(id: delivered_to_account_id)
            return account if account.present?
          end

          recipients(object).find(&:local?)
        end

        def recipients(object)
          [*object['to'], *object['cc']].filter_map { |value| account_for(uri_of(value)) }
        end

        def local_account_for_target(json)
          account = account_for(uri_of(json['target']))
          account if account&.local?
        end

        def account_for(uri)
          return if uri.blank?

          ActivityPub::TagManager.instance.uri_to_resource(uri, ::Account)
        rescue Addressable::URI::InvalidURIError
          nil
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
