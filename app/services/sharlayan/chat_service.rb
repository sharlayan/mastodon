# frozen_string_literal: true

class Sharlayan::ChatService
  include Redisable

  class Error < StandardError; end
  class Forbidden < Error; end

  def create_conversation(account, type:, account_ids: [], title: nil, description: nil)
    raise Error, 'Unknown chat type' unless %w(direct group).include?(type.to_s)

    requested_ids = account_ids.map(&:to_s).uniq
    requested_participant_ids = requested_ids.reject { |id| id == account.id.to_s }
    participant_limit = type.to_s == 'direct' ? 1 : Setting.chat_max_group_members - 1
    raise Error, 'The group has too many members' if requested_participant_ids.size > participant_limit

    participants = Account.where(id: requested_ids).to_a
    raise Error, 'One or more chat participants were not found' unless participants.size == requested_ids.size
    raise Error, 'Chat federation is disabled' if participants.any?(&:remote?) && !Setting.chat_federation_enabled

    type.to_s == 'direct' ? create_direct(account, participants) : create_group(account, participants, title, description)
  end

  def create_message(account, conversation, text:, reply_to_id: nil, media_ids: [])
    membership = membership!(account, conversation)
    ensure_conversation_writable!(conversation)
    ensure_direct_participants_not_blocked!(account, conversation)

    reply_to = conversation.messages.find_by(id: reply_to_id) if reply_to_id.present?
    raise Error, 'Reply target was not found' if reply_to_id.present? && reply_to.nil?

    attachments = media_attachments(account, media_ids)

    message = nil
    conversation.with_lock do
      message = conversation.messages.build(account: account, text: text.to_s.strip.presence, reply_to: reply_to)
      message.pending_media_attachments = attachments
      message.save!
      message.update!(uri: local_message_uri(message)) if message.uri.nil? && account.local?
      attachments.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }
      conversation.update!(last_message: message)
      membership.update!(last_read_message: message)
    end
    broadcast(conversation, 'chat.message', message, REST::ChatMessageSerializer)
    notify_members(conversation, message)
    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.create(message))
    message
  end

  def update_message(account, message, text:)
    raise Forbidden unless message.account_id == account.id

    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(account, message.chat_conversation)
    raise Error, 'Deleted messages cannot be edited' if message.deleted?

    message.update!(text: text.to_s.strip.presence, edited_at: Time.current)
    broadcast(message.chat_conversation, 'chat.message_update', message, REST::ChatMessageSerializer)
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.update(message))
    message
  end

  def delete_message(account, message)
    raise Forbidden unless message.account_id == account.id

    return hide_message(account, message) if !message.chat_conversation.accounts.remote.exists? && hide_instead_of_delete?(message)

    message.transaction do
      message.reactions.destroy_all
      message.chat_message_media_attachments.destroy_all
      message.update!(text: nil, deleted_at: Time.current)
    end
    broadcast(message.chat_conversation, 'chat.message_delete', { id: message.id.to_s, conversation_id: message.chat_conversation_id.to_s })
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.delete(message))
    message
  end

  def mark_read(account, conversation, message_id: nil)
    membership = membership!(account, conversation)
    message = message_id.present? ? conversation.messages.find(message_id) : conversation.last_message
    if message && (membership.last_read_message_id.nil? || message.id > membership.last_read_message_id)
      membership.update!(last_read_message: message)
      broadcast_to(account, 'chat.read', { conversation_id: conversation.id.to_s, message_id: message.id.to_s })
    end
    membership
  end

  def react(account, message, reaction)
    membership!(account, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(account, message.chat_conversation)
    record = message.with_lock do
      raise Error, 'Deleted messages cannot receive reactions' if message.deleted?
      raise Error, 'The message has too many reactions' if message.reactions.count >= 100

      message.reactions.create!(account: account, reaction: reaction)
    end
    broadcast(message.chat_conversation, 'chat.reaction', REST::ChatMessageReactionSerializer.new(record).as_json)
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.reaction(message, account, reaction))
    record
  end

  def unreact(account, message, reaction)
    membership!(account, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    record = message.reactions.find_by!(account: account, reaction: reaction)
    record.destroy!
    broadcast(message.chat_conversation, 'chat.reaction_delete', { message_id: message.id.to_s, account_id: account.id.to_s, reaction: reaction })
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.undo_reaction(message, account, reaction))
  end

  def invite(account, conversation, invitee)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    ensure_conversation_writable!(conversation)
    raise Error, 'Chat federation is disabled' if invitee.remote? && !Setting.chat_federation_enabled
    raise Error, 'Account is already a member' if conversation.memberships.exists?(account: invitee)
    raise Forbidden if blocked_in_either_direction?(account, invitee)
    raise Forbidden unless !invitee.local? || invitee.user&.settings&.[](:chat_allow_group_invites)

    invitation = conversation.with_lock do
      existing_invitation = conversation.invitations.pending.find_by(invitee_account: invitee)
      next existing_invitation if existing_invitation

      ensure_group_capacity!(conversation, include_pending: true)
      conversation.invitations.create!(inviter_account: account, invitee_account: invitee)
    end
    if invitee.local?
      broadcast_to(invitee, 'chat.invitation', invitation, REST::ChatInvitationSerializer)
    else
      deliver_to_account(account, Sharlayan::ChatFederation::Payload.invite(conversation, invitee), invitee)
    end
    invitation
  end

  def accept_invitation(account, invitation)
    raise Forbidden unless invitation.invitee_account_id == account.id && invitation.pending?

    ensure_conversation_writable!(invitation.chat_conversation)
    raise Forbidden if blocked_in_either_direction?(invitation.inviter_account, account)

    conversation = invitation.chat_conversation
    conversation.with_lock do
      invitation.lock!
      raise Forbidden unless invitation.pending?

      ensure_group_capacity!(conversation)
      conversation.memberships.find_or_create_by!(account: account)
      invitation.update!(state: :accepted)
    end
    if conversation.owner_account.remote?
      deliver_to_account(account, Sharlayan::ChatFederation::Payload.accept(invitation), conversation.owner_account)
    else
      broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
      deliver_roster_after_join(conversation, account)
    end
    conversation
  end

  def reject_invitation(account, invitation)
    raise Forbidden unless invitation.invitee_account_id == account.id && invitation.pending?

    invitation.update!(state: :rejected)
    owner = invitation.chat_conversation.owner_account
    return unless owner&.remote?

    deliver_to_account(invitation.invitee_account, Sharlayan::ChatFederation::Payload.reject(invitation), owner)
  end

  def cancel_invitation(account, invitation)
    raise Forbidden unless invitation.inviter_account_id == account.id && invitation.pending?

    invitation.update!(state: :cancelled)
    return unless invitation.invitee_account.remote?

    deliver_to_account(account, Sharlayan::ChatFederation::Payload.cancel(invitation), invitation.invitee_account)
  end

  def leave(account, conversation)
    membership = membership!(account, conversation)
    raise Error, 'The owner cannot leave the room' if membership.owner?

    membership.destroy!
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.remove(conversation, account))
  end

  def mute(account, conversation, muted:)
    membership = membership!(account, conversation)
    membership.update!(muted: muted)
    membership
  end

  def archive(account, conversation, archived:)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    conversation.update!(archived_at: archived ? Time.current : nil)
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    conversation
  end

  def update_conversation(account, conversation, attributes)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    ensure_conversation_writable!(conversation)
    conversation.update!(attributes)
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.update_room(conversation))
    conversation
  end

  def destroy_conversation(account, conversation)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.delete_room(conversation)) if conversation.local?
    destroy_and_announce(conversation)
  end

  # Removes every trace of an account's chat activity. DeleteAccountService keeps
  # the account record by default, so `dependent: :destroy` alone is not enough.
  def purge_account(account, federate: true)
    federate &&= account.local?

    account.owned_chat_conversations.find_each do |conversation|
      deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.delete_room(conversation)) if federate && conversation.chat_group?
      destroy_and_announce(conversation)
    end
    account.chat_memberships.includes(:chat_conversation).find_each { |membership| purge_membership(membership, federate: federate) }
    account.chat_message_reactions.in_batches.delete_all
    purge_messages(account)
    ChatInvitation.where(invitee_account: account).or(ChatInvitation.where(inviter_account: account)).in_batches.delete_all
  end

  def receive_direct_message(recipient, actor, uri:, text:, created_at: nil, attachments: [])
    key = [recipient.id, actor.id].sort.join(':')
    conversation = ChatConversation.find_by(direct_key: key)

    # As with local chats, the policy only gates starting a conversation: it must not
    # drop replies to a chat the recipient started. create_remote_message checks blocks.
    if conversation.nil?
      raise Forbidden unless direct_chat_allowed?(actor, recipient)

      conversation = create_remote_direct(recipient, actor, key)
    end

    create_remote_message(conversation, actor, uri: uri, text: text, created_at: created_at, attachments: attachments)
  end

  def receive_group_message(actor, room_uri:, uri:, text:, created_at: nil, attachments: [])
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?
    raise Forbidden unless conversation.memberships.exists?(account: actor)

    create_remote_message(conversation, actor, uri: uri, text: text, created_at: created_at, attachments: attachments)
  end

  def receive_invite(invitee, actor, room_uri:, title:, description: nil)
    raise Forbidden unless invitee.local?
    raise Forbidden unless invitee.user&.settings&.[](:chat_allow_group_invites)
    raise Forbidden if blocked_in_either_direction?(invitee, actor)

    conversation = ChatConversation.find_by(uri: room_uri)
    raise Forbidden if conversation && (!conversation.chat_group? || conversation.owner_account_id != actor.id)
    raise Forbidden unless conversation || (actor.remote? && same_origin?(room_uri, actor.uri))

    conversation ||= ChatConversation.create!(uri: room_uri) do |record|
      record.conversation_type = :group
      record.owner_account = actor
      record.title = title.presence || actor.username
      record.description = description
    end
    conversation.memberships.create_with(role: :owner).find_or_create_by!(account: actor) if conversation.owner_account_id == actor.id

    conversation.invitations.pending.find_by(invitee_account: invitee) ||
      conversation.invitations.create!(inviter_account: actor, invitee_account: invitee)
  end

  def receive_accept(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?

    invitation = conversation.invitations.pending.find_by(invitee_account: actor)
    raise Error, 'Invitation not found' if invitation.nil?

    conversation.with_lock do
      invitation.lock!
      raise Forbidden unless invitation.pending?

      ensure_conversation_writable!(conversation)
      raise Forbidden if blocked_in_either_direction?(invitation.inviter_account, actor)

      ensure_group_capacity!(conversation)
      conversation.memberships.find_or_create_by!(account: actor)
      invitation.update!(state: :accepted)
    end

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    deliver_roster_after_join(conversation, actor)
    conversation
  end

  def receive_reject(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?

    conversation.invitations.pending.find_by(invitee_account: actor)&.update!(state: :rejected)
  end

  def receive_cancel(actor, room_uri:, invitee:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    invitation = conversation.invitations.pending.find_by(inviter_account: actor, invitee_account: invitee)
    invitation&.update!(state: :cancelled)
  end

  def receive_add(actor, room_uri:, account_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    account = ActivityPub::TagManager.instance.uri_to_resource(account_uri, Account)
    account ||= ActivityPub::FetchRemoteAccountService.new.call(account_uri) unless ActivityPub::TagManager.instance.local_uri?(account_uri)
    raise Error, 'Unknown account' if account.nil?
    raise Forbidden if account.local? && !conversation.memberships.exists?(account: account)

    conversation.memberships.find_or_create_by!(account: account)
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    conversation
  end

  def receive_remove(actor, room_uri:, account_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?

    account = ActivityPub::TagManager.instance.uri_to_resource(account_uri, Account)
    return if account.nil?
    raise Forbidden unless actor.id == account.id || conversation.owner_account_id == actor.id

    conversation.memberships.find_by(account: account)&.destroy!
    # The removed account no longer receives broadcasts to the room's members.
    broadcast_to(account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s }) if account.local?
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    relay_departure(conversation, account)
  end

  def receive_room_update(actor, room_uri:, title:, description: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    conversation.update!(title: title.presence || conversation.title, description: description)
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    conversation
  end

  def receive_room_delete(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    destroy_and_announce(conversation)
  end

  def update_remote_message(actor, message, text:, edited_at:)
    raise Forbidden unless message.account_id == actor.id
    raise Error, 'Deleted messages cannot be edited' if message.deleted?

    membership!(actor, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(actor, message.chat_conversation)

    message.with_lock do
      raise Error, 'Deleted messages cannot be edited' if message.deleted?
      return message if edited_at && message.edited_at && edited_at <= message.edited_at

      message.update!(text: text.to_s.strip.presence, edited_at: edited_at || Time.current)
    end
    broadcast(message.chat_conversation, 'chat.message_update', message, REST::ChatMessageSerializer)
    message
  end

  def delete_remote_message(actor, message)
    raise Forbidden unless message.account_id == actor.id

    message.transaction do
      message.reactions.destroy_all
      message.chat_message_media_attachments.destroy_all
      message.update!(text: nil, deleted_at: Time.current)
    end
    broadcast(message.chat_conversation, 'chat.message_delete', { id: message.id.to_s, conversation_id: message.chat_conversation_id.to_s })
    message
  end

  def react_remote(actor, message, reaction)
    membership!(actor, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(actor, message.chat_conversation)
    raise Error, 'Deleted messages cannot receive reactions' if message.deleted?
    raise Forbidden if message.account_id == actor.id

    record = message.reactions.find_or_create_by!(account: actor, reaction: reaction)
    broadcast(message.chat_conversation, 'chat.reaction', REST::ChatMessageReactionSerializer.new(record).as_json)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def unreact_remote(actor, message, reaction)
    membership!(actor, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    message.reactions.find_by(account: actor, reaction: reaction)&.destroy!
    broadcast(message.chat_conversation, 'chat.reaction_delete', { message_id: message.id.to_s, account_id: actor.id.to_s, reaction: reaction })
  end

  def remember_tombstone(uri, actor)
    raise Forbidden unless same_origin?(uri, actor.uri)

    redis.setex("chat_delete_upon_arrival:#{actor.id}:#{uri}", 6.hours.seconds, true)
  end

  def tombstone?(uri, actor)
    redis.exists?("chat_delete_upon_arrival:#{actor.id}:#{uri}")
  end

  private

  def create_remote_message(conversation, actor, uri:, text:, created_at:, attachments:)
    return nil if tombstone?(uri, actor)

    existing = ChatMessage.find_by(uri: uri)
    return existing if existing
    raise Forbidden unless conversation.memberships.exists?(account: actor)

    ensure_conversation_writable!(conversation)
    ensure_direct_participants_not_blocked!(actor, conversation)

    message = nil
    conversation.with_lock do
      message = conversation.messages.build(
        account: actor,
        uri: uri,
        text: text.to_s.strip.presence,
        created_at: created_at || Time.current
      )
      media = attachments.filter_map { |attachment| incoming_media(actor, attachment) }
      message.pending_media_attachments = media
      message.save!
      media.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }
      conversation.update!(last_message: message)
    end
    broadcast(conversation, 'chat.message', message, REST::ChatMessageSerializer)
    notify_members(conversation, message)
    message
  end

  def incoming_media(actor, document)
    url = document['url']
    url = url.first if url.is_a?(Array)
    url = url['href'] || url['url'] if url.is_a?(Hash)
    return unless http_url?(url)

    MediaAttachment.create!(
      account: actor,
      remote_url: url.to_s,
      file_content_type: document['mediaType'].presence || 'image/jpeg',
      description: document['name']
    )
  end

  def destroy_and_announce(conversation)
    local_accounts = Account.local.where(id: conversation.memberships.select(:account_id))
      .or(Account.local.where(id: conversation.invitations.pending.select(:invitee_account_id))).to_a
    conversation_id = conversation.id.to_s

    conversation.destroy!
    local_accounts.each { |account| broadcast_to(account, 'chat.conversation_delete', { conversation_id: conversation_id }) }
  end

  def purge_membership(membership, federate:)
    conversation = membership.chat_conversation
    account_id = membership.account_id

    if conversation.chat_group?
      deliver_to_conversation(membership.account, conversation, Sharlayan::ChatFederation::Payload.remove(conversation, membership.account)) if federate
      membership.destroy!
      broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account_id.to_s })
    else
      # Removing one side of a direct chat removes the conversation with it.
      destroy_and_announce(conversation)
    end
  end

  def purge_messages(account)
    conversation_ids = account.chat_messages.distinct.pluck(:chat_conversation_id)
    account.chat_messages.in_batches.destroy_all

    # The foreign key nullifies the pointer, which would misplace the room in the list.
    ChatConversation.where(id: conversation_ids, last_message_id: nil).find_each do |conversation|
      conversation.update!(last_message: conversation.messages.first)
    end
  end

  # A member's own server only reaches the people it knows about, so the owner's
  # server tells the rest of the room, as it does when a member joins.
  def relay_departure(conversation, account)
    owner = conversation.owner_account
    return unless owner&.local? && account.remote?

    deliver_to_conversation(owner, conversation, Sharlayan::ChatFederation::Payload.remove(conversation, account, actor: owner))
  end

  def deliver_roster_after_join(conversation, joined_account)
    owner = conversation.owner_account
    return if owner.nil?

    members = conversation.accounts.to_a
    members.each do |member|
      next if member.id == joined_account.id || member.id == owner.id || !member.remote? || member.inbox_url.blank?

      payload = Sharlayan::ChatFederation::Payload.add(conversation, joined_account)
      deliver_to_account(owner, payload, member)
    end
    if joined_account.remote?
      members.each do |member|
        next if member.id == joined_account.id || member.id == owner.id

        payload = Sharlayan::ChatFederation::Payload.add(conversation, member)
        deliver_to_account(owner, payload, joined_account)
      end
    end
  end

  def deliver_to_conversation(actor, conversation, payload)
    return unless Setting.chat_federation_enabled

    Sharlayan::ChatFederation::Delivery.call(actor: actor, conversation: conversation, payload: payload, except_account_id: actor.id)
  end

  def deliver_to_account(actor, payload, account)
    return unless Setting.chat_federation_enabled
    return if account.inbox_url.blank?

    ActivityPub::DeliveryWorker.perform_async(payload.to_json, actor.id, account.inbox_url)
  end

  def same_origin?(first, second)
    first_uri = Addressable::URI.parse(first)
    second_uri = Addressable::URI.parse(second)
    first_uri.host.present? && %w(http https).include?(first_uri.scheme) && first_uri.origin == second_uri.origin
  rescue Addressable::URI::InvalidURIError
    false
  end

  def http_url?(url)
    %w(http https).include?(Addressable::URI.parse(url.to_s).scheme)
  rescue Addressable::URI::InvalidURIError
    false
  end

  def local_message_uri(message)
    "#{local_base_url}/chat/messages/#{message.id}"
  end

  def local_room_uri(conversation)
    "#{local_base_url}/chat/rooms/#{conversation.id}"
  end

  def local_base_url
    "#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.web_domain}"
  end

  def hide_instead_of_delete?(message)
    RoleplayModeHelper.roleplay_mode? || Setting.chat_soft_delete_enabled || message.created_at <= Setting.chat_delete_window_hours.hours.ago
  end

  def hide_message(account, message)
    message.update!(hidden_at: Time.current)
    broadcast_to(account, 'chat.message_hide', { id: message.id.to_s, conversation_id: message.chat_conversation_id.to_s })
    message
  end

  def create_direct(account, participants)
    others = participants.reject { |participant| participant.id == account.id }.uniq(&:id)
    raise Error, 'A direct chat requires exactly one other account' unless others.one?

    other = others.first
    raise Forbidden if blocked_in_either_direction?(account, other)

    key = [account.id, other.id].sort.join(':')
    conversation = ChatConversation.find_by(direct_key: key)
    return conversation if conversation
    raise Forbidden unless direct_chat_allowed?(account, other)

    return create_remote_direct(account, other, key) if other.remote?

    ChatConversation.transaction do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: key)
      conversation.memberships.create!([{ account: account }, { account: other }])
      conversation
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def create_group(account, participants, title, description)
    invitees = participants.reject { |participant| participant.id == account.id }
    raise Error, 'The group has too many members' if invitees.size + 1 > Setting.chat_max_group_members
    raise Forbidden if invitees.any? { |participant| blocked_in_either_direction?(account, participant) }
    raise Forbidden unless invitees.all? { |participant| !participant.local? || participant.user&.settings&.[](:chat_allow_group_invites) }

    conversation = ChatConversation.transaction do
      record = ChatConversation.create!(conversation_type: :group, owner_account: account, title: title, description: description)
      record.update!(uri: local_room_uri(record))
      record.memberships.create!(account: account, role: :owner)
      invitees.each do |participant|
        record.invitations.create!(inviter_account: account, invitee_account: participant)
      end
      record
    end

    conversation.invitations.pending.where(invitee_account: invitees.select(&:remote?)).find_each do |invitation|
      deliver_to_account(account, Sharlayan::ChatFederation::Payload.invite(conversation, invitation.invitee_account), invitation.invitee_account)
    end
    conversation
  end

  def create_remote_direct(account, other, key)
    ChatConversation.transaction do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: key)
      conversation.memberships.create!([{ account: account }, { account: other }])
      conversation
    end
  rescue ActiveRecord::RecordNotUnique
    ChatConversation.find_by!(direct_key: key)
  end

  def membership!(account, conversation)
    conversation.memberships.find_by!(account: account)
  rescue ActiveRecord::RecordNotFound
    raise Forbidden
  end

  def ensure_conversation_writable!(conversation)
    raise Error, 'Archived conversations are read-only' if conversation.archived?
  end

  def ensure_direct_participants_not_blocked!(account, conversation)
    return unless conversation.chat_direct?

    other_accounts = conversation.accounts.where.not(id: account.id)
    raise Forbidden if other_accounts.any? { |other_account| blocked_in_either_direction?(account, other_account) }
  end

  def ensure_group_capacity!(conversation, include_pending: false)
    size = conversation.memberships.count
    size += conversation.invitations.pending.count if include_pending
    raise Error, 'The group has too many members' if size >= Setting.chat_max_group_members
  end

  def blocked_in_either_direction?(first_account, second_account)
    first_account.blocking_or_domain_blocking?(second_account) || second_account.blocking_or_domain_blocking?(first_account)
  end

  def media_attachments(account, ids)
    normalized_ids = ids.map(&:to_s).uniq
    raise Error, "A chat message can contain up to #{Setting.chat_max_attachments} attachments" if normalized_ids.size > Setting.chat_max_attachments

    attachments = MediaAttachment.unattached.where(id: normalized_ids, account: account).to_a
    raise Error, 'One or more media attachments were not found' unless attachments.size == normalized_ids.size
    raise Error, 'One or more media attachments are already in use' if ChatMessageMediaAttachment.exists?(media_attachment_id: normalized_ids)
    raise Error, 'One or more media attachments are still being processed' if attachments.any?(&:not_processed?)

    attachments
  end

  def direct_chat_allowed?(sender, recipient)
    return false if blocked_in_either_direction?(sender, recipient)

    if recipient.local?
      policy = recipient.user&.settings&.[](:chat_policy) || 'nobody'
      case policy
      when 'everyone' then true
      when 'followers' then recipient.followed_by?(sender)
      when 'following' then recipient.following?(sender)
      when 'mutual', 'mutuals' then recipient.following?(sender) && recipient.followed_by?(sender)
      else false
      end
    else
      return false if recipient.can_chat == false

      case recipient.chat_scope.presence || 'mutual'
      when 'everyone' then true
      when 'followers' then recipient.followed_by?(sender)
      when 'following' then recipient.following?(sender)
      when 'mutual' then recipient.following?(sender) && recipient.followed_by?(sender)
      else false
      end
    end
  end

  def broadcast(conversation, event, object, serializer = nil)
    conversation.memberships.includes(:account).find_each do |membership|
      payload = serializer ? serializer.new(object, current_account: membership.account).as_json : object
      broadcast_to(membership.account, event, payload)
    end
  end

  def broadcast_to(account, event, object, serializer = nil)
    payload = serializer ? serializer.new(object, current_account: account).as_json : object
    redis.publish("timeline:#{account.id}", JSON.generate(event: event, payload: JSON.generate(payload)))
  end

  def notify_members(conversation, message)
    conversation.memberships.includes(account: :user).where.not(account_id: message.account_id).find_each do |membership|
      next if membership.muted? || !membership.account.user&.settings&.[](:chat_notifications)

      broadcast_to(membership.account, 'chat.notification', message, REST::ChatMessageSerializer)
    end
  end
end
