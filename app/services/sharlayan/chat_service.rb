# frozen_string_literal: true

class Sharlayan::ChatService
  include DomainControlHelper
  include Redisable

  class Error < StandardError; end
  class Forbidden < Error; end

  MAX_PENDING_REMOTE_ROOMS = 100
  MAX_REMOTE_ROOM_MEMBERS = 1000
  MAX_ROOM_TITLE_LENGTH = 256
  MAX_ROOM_DESCRIPTION_LENGTH = 2048
  INVITE_CANCEL_TTL = 6.hours
  ROOM_TOMBSTONE_TTL = 30.days
  UNKNOWN_ROOM_TOMBSTONE_TTL = 6.hours
  MAX_TOMBSTONED_ROOM_MESSAGES = 1000
  ACCEPT_DELIVERY_GRACE = 5.minutes

  def self.room_tombstone_key(uri)
    "chat_room_tombstone:#{Digest::SHA256.hexdigest(uri.to_s)}"
  end

  def create_conversation(account, type:, account_ids: [], title: nil, description: nil, refresh: true)
    raise Error, 'Unknown chat type' unless %w(direct group).include?(type.to_s)

    requested_ids = account_ids.map(&:to_s).uniq
    requested_participant_ids = requested_ids.reject { |id| id == account.id.to_s }
    participant_limit = type.to_s == 'direct' ? 1 : Setting.chat_max_group_members - 1
    raise Error, 'The group has too many members' if requested_participant_ids.size > participant_limit

    participants = Account.without_suspended.where(id: requested_ids).to_a
    raise Error, 'One or more chat participants were not found' unless participants.size == requested_ids.size
    raise Error, 'Chat federation is disabled' if participants.any?(&:remote?) && !Setting.chat_federation_enabled

    participants.each { |participant| refresh_remote_account(participant) } if refresh

    type.to_s == 'direct' ? create_direct(account, participants) : create_group(account, participants, title, description)
  end

  # Leaves no empty conversation behind when the message is refused. The remote account is
  # refreshed first, as that is a request to another server and must not hold the transaction open.
  def create_direct_message(account, recipient, text:, media_ids: [])
    refresh_remote_account(recipient)

    ChatConversation.transaction do
      conversation = create_conversation(account, type: :direct, account_ids: [recipient.id], refresh: false)
      create_message(account, conversation, text: text, media_ids: media_ids)
    end
  end

  def create_message(account, conversation, text:, reply_to_id: nil, media_ids: [])
    membership = membership!(account, conversation)
    ensure_conversation_writable!(conversation)
    ensure_federation_available!(conversation)
    ensure_direct_participants_not_blocked!(account, conversation)
    ensure_direct_recipient_not_suspended!(account, conversation)

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
    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.create(message), message: message)
    message
  end

  def update_message(account, message, text:)
    raise Forbidden unless message.account_id == account.id
    raise Error, 'This message can no longer be edited' unless message.within_delete_window?

    ensure_conversation_writable!(message.chat_conversation)
    ensure_federation_available!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(account, message.chat_conversation)
    ensure_direct_recipient_not_suspended!(account, message.chat_conversation)
    message.with_lock do
      raise Error, 'Deleted messages cannot be edited' if message.deleted?

      edited_at = Time.current
      edited_at = [edited_at, message.edited_at + Rational(1, 1000)].max if message.edited_at
      keep_previous_text(message, text)
      message.update!(text: text.to_s.strip.presence, edited_at: edited_at)
    end
    broadcast(message.chat_conversation, 'chat.message_update', message, REST::ChatMessageSerializer)
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.update(message), message: message)
    message
  end

  def delete_message(account, message)
    raise Forbidden unless message.account_id == account.id

    return hide_message(account, message) if hide_instead_of_delete?(message)
    return message unless tombstone_message(message)

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
    raise Forbidden if message.account_id == account.id

    ensure_conversation_writable!(message.chat_conversation)
    ensure_federation_available!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(account, message.chat_conversation)
    ensure_direct_recipient_not_suspended!(account, message.chat_conversation)
    record = message.with_lock do
      raise Error, 'Deleted messages cannot receive reactions' if message.deleted?

      existing = message.reactions.find_by(account: account, reaction: reaction)
      next existing if existing
      raise Error, 'The message has too many reactions' if message.reactions.count >= 100

      message.reactions.create!(account: account, reaction: reaction)
    end
    return record unless record.previously_new_record?

    broadcast(message.chat_conversation, 'chat.reaction', REST::ChatMessageReactionSerializer.new(record).as_json)
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.reaction(message, account, reaction, reaction_id: record.id))
    record
  end

  def unreact(account, message, reaction)
    membership!(account, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    record = message.with_lock { message.reactions.find_by(account: account, reaction: reaction)&.destroy! }
    return if record.nil?

    broadcast(message.chat_conversation, 'chat.reaction_delete', { message_id: message.id.to_s, account_id: account.id.to_s, reaction: reaction })
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.undo_reaction(message, account, reaction, reaction_id: record.id))
  end

  def invite(account, conversation, invitee)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    ensure_conversation_writable!(conversation)
    raise Error, 'Chat federation is disabled' if invitee.remote? && !Setting.chat_federation_enabled
    raise Error, 'Account is already a member' if conversation.memberships.exists?(account: invitee)
    raise Forbidden if invitee.suspended? || blocked_in_either_direction?(account, invitee) || silenced_for?(account, invitee)

    refresh_remote_account(invitee)
    raise Forbidden unless accepts_group_invites?(invitee)

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
    raise Forbidden if blocked_in_either_direction?(invitation.inviter_account, account) || owner_refused?(invitation.chat_conversation.owner_account)

    conversation = invitation.chat_conversation
    joined = conversation.with_lock do
      invitation.lock!
      raise Forbidden unless invitation.pending?

      ensure_group_capacity!(conversation) unless conversation.memberships.exists?(account: account)
      Sharlayan::ChatFederation::Roster.advance(conversation, account, Time.current)
      membership = conversation.memberships.find_or_create_by!(account: account)
      invitation.update!(state: :accepted)
      membership.previously_new_record?
    end
    if conversation.owner_account.remote?
      deliver_to_account(account, Sharlayan::ChatFederation::Payload.accept(invitation), conversation.owner_account)
    else
      broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
      deliver_roster_after_join(conversation, account)
    end
    broadcast(conversation, 'chat.member_join', { conversation_id: conversation.id.to_s, account_id: account.id.to_s }) if joined
    conversation
  end

  def reject_invitation(account, invitation)
    raise Forbidden unless invitation.invitee_account_id == account.id && invitation.pending?

    invitation.update!(state: :rejected)
    owner = invitation.chat_conversation.owner_account
    deliver_to_account(invitation.invitee_account, Sharlayan::ChatFederation::Payload.reject(invitation), owner) if owner&.remote?
    invitation.chat_conversation.destroy_if_unused!
  end

  def cancel_invitation(account, invitation)
    raise Forbidden unless invitation.inviter_account_id == account.id && invitation.pending?

    invitation.update!(state: :cancelled)
    if invitation.invitee_account.local?
      broadcast_to(invitation.invitee_account, 'chat.invitation', invitation, REST::ChatInvitationSerializer)
    else
      deliver_to_account(account, Sharlayan::ChatFederation::Payload.cancel(invitation), invitation.invitee_account)
    end
    invitation.chat_conversation.destroy_if_unused!
  end

  def leave(account, conversation)
    membership = membership!(account, conversation)
    raise Error, 'The owner cannot leave the room' if membership.owner?

    raise Error, 'Only group chats can be left' unless conversation.chat_group?

    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.remove(conversation, account))
    membership.destroy!
    forget_acceptance(conversation, account)
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    schedule_abandoned_room_cleanup(conversation)
  end

  def mute(account, conversation, muted:)
    membership = membership!(account, conversation)
    membership.update!(muted: muted)
    membership
  end

  def kick(account, conversation, target)
    recipients = conversation.with_lock do
      membership = membership!(account, conversation)
      raise Forbidden unless conversation.chat_group? && membership.owner? && conversation.owner_account_id == account.id
      raise Forbidden if target.id == account.id

      target_membership = conversation.memberships.find_by!(account: target)
      raise Forbidden if target_membership.owner?

      remote_accounts = conversation.accounts.remote.to_a
      target_membership.destroy!
      remote_accounts
    end

    payload = Sharlayan::ChatFederation::Payload.remove(conversation, target, actor: account)
    recipients.uniq(&:preferred_inbox_url).each { |recipient| deliver_to_account(account, payload, recipient) }
    broadcast_to(target, 'chat.conversation_delete', { conversation_id: conversation.id.to_s }) if target.local?
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: target.id.to_s })
    conversation
  end

  def archive(account, conversation, archived:)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    conversation.with_lock do
      conversation.archived_at = archived ? (conversation.archived_at || Time.current) : nil
      save_room_state!(conversation)
    end
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    deliver_room_state(account, conversation, Sharlayan::ChatFederation::Payload.update_room(conversation))
    conversation
  end

  def update_conversation(account, conversation, attributes)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    conversation.with_lock do
      ensure_conversation_writable!(conversation)
      conversation.assign_attributes(attributes)
      save_room_state!(conversation)
    end
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    deliver_room_state(account, conversation, Sharlayan::ChatFederation::Payload.update_room(conversation))
    conversation
  end

  def destroy_conversation(account, conversation)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    deliver_room_state(account, conversation, Sharlayan::ChatFederation::Payload.delete_room(conversation)) if conversation.local?
    destroy_and_announce(conversation)
  end

  def purge_account(account, federate: true)
    federate &&= account.local?

    account.owned_chat_conversations.find_each do |conversation|
      deliver_room_state(account, conversation, Sharlayan::ChatFederation::Payload.delete_room(conversation)) if federate && conversation.chat_group?
      destroy_and_announce(conversation)
    end
    account.chat_memberships.includes(:chat_conversation).find_each { |membership| purge_membership(membership, federate: federate) }
    account.chat_message_reactions.in_batches.delete_all
    purge_messages(account)
    purge_invitations(account)
  end

  # This server decides who is in the rooms it owns, so a suspension ends their membership here for good.
  # A room owned by another server is left to that server, and a direct conversation comes back with the account.
  def remove_suspended_account(account)
    return unless account.remote?

    rooms = ChatConversation.chat_group.local_only.where.not(owner_account_id: nil)
    account.chat_memberships.where(chat_conversation: rooms).includes(chat_conversation: :owner_account).find_each do |membership|
      conversation = membership.chat_conversation
      kick(conversation.owner_account, conversation, account)
    end
    ChatInvitation.pending.where(invitee_account: account, chat_conversation: rooms).includes(:inviter_account).find_each do |invitation|
      cancel_invitation(invitation.inviter_account, invitation)
    end
  end

  def destroy_conversation_as_admin(conversation)
    return destroy_and_announce(conversation) unless conversation.chat_group? && conversation.local? && conversation.owner_account.present?

    deliver_room_state(conversation.owner_account, conversation, Sharlayan::ChatFederation::Payload.delete_room(conversation))
    destroy_and_announce(conversation)
  end

  def remove_abandoned_conversation(conversation)
    destroy_and_announce(conversation)
  end

  def resolve_account(uri)
    account_from_uri(uri)
  end

  def receive_direct_message(recipient, actor, uri:, text:, created_at: nil, edited_at: nil, attachments: [], reply_to_uri: nil)
    key = [recipient.id, actor.id].sort.join(':')

    ChatConversation.transaction do
      conversation = ChatConversation.lock.find_by(direct_key: key)

      if conversation.nil?
        raise Forbidden unless direct_chat_allowed?(actor, recipient)

        conversation = create_direct_record(recipient, actor, key)
      end

      create_remote_message(conversation, actor, uri: uri, text: text, created_at: created_at, edited_at: edited_at, attachments: attachments, reply_to_uri: reply_to_uri)
    end
  end

  def receive_group_message(actor, room_uri:, uri:, text:, created_at: nil, edited_at: nil, attachments: [], reply_to_uri: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    if conversation.nil?
      raise Error, 'The chat room was deleted' if room_tombstoned?(room_uri)

      raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat room'
    end

    ensure_conversation_writable!(conversation)
    ensure_room_member!(conversation, actor)

    unless conversation.accounts.local.exists?
      raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat membership' if conversation.invitations.pending.joins(:invitee_account).merge(Account.local).exists?

      raise Forbidden
    end

    message = create_remote_message(conversation, actor, uri: uri, text: text, created_at: created_at, edited_at: edited_at, attachments: attachments, reply_to_uri: reply_to_uri)
    relay_to_room(conversation, message)
    message
  end

  def receive_invite(invitee, actor, room_uri:, title:, description: nil, archived: nil, updated: nil, published: nil)
    raise Forbidden unless invitee.local?
    raise Forbidden unless invitee.user&.settings&.[](:chat_allow_group_invites)
    raise Forbidden if blocked_in_either_direction?(invitee, actor) || silenced_for?(actor, invitee)
    raise Error, 'Too many pending invitations from this account' if actor.remote? && ChatInvitation.pending.joins(:chat_conversation).where(chat_conversations: { owner_account_id: actor.id }).count >= MAX_PENDING_REMOTE_ROOMS

    invitation = ChatConversation.transaction do
      conversation = ChatConversation.lock.find_by(uri: room_uri)
      raise Forbidden if conversation && (!conversation.chat_group? || conversation.owner_account_id != actor.id)
      raise Forbidden unless conversation || (actor.remote? && same_origin?(room_uri, actor.uri))

      conversation ||= ChatConversation.new(uri: room_uri, conversation_type: :group, owner_account: actor)
      apply_remote_room_state(conversation, title: (title if title.is_a?(String)).presence || conversation.title || actor.username, description: description, archived: archived, updated: updated)
      ensure_conversation_writable!(conversation)
      conversation.memberships.create_with(role: :owner).find_or_create_by!(account: actor) if conversation.owner_account_id == actor.id
      Sharlayan::ChatFederation::Roster.advance(conversation, invitee, published)

      next acknowledge_repeated_invite(conversation, actor, invitee) if conversation.memberships.exists?(account: invitee)

      ensure_group_capacity!(conversation)
      conversation.invitations.pending.find_by(invitee_account: invitee) ||
        conversation.invitations.create!(inviter_account: actor, invitee_account: invitee)
    end
    ChatConversationCleanupWorker.perform_in(ChatConversationCleanupWorker::CLEANUP_DELAY, invitation.chat_conversation_id) if actor.remote?
    broadcast_to(invitee, 'chat.invitation', invitation, REST::ChatInvitationSerializer) if invitation.pending?
    invitation.reload
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def receive_accept(actor, room_uri:, published: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?

    invitation = conversation.invitations.pending.find_by(invitee_account: actor)
    raise Error, 'Invitation not found' if invitation.nil?

    joined = conversation.with_lock do
      invitation.lock!
      raise Forbidden unless invitation.pending?

      ensure_conversation_writable!(conversation)
      raise Forbidden if blocked_in_either_direction?(invitation.inviter_account, actor)

      ensure_group_capacity!(conversation) unless conversation.memberships.exists?(account: actor)
      Sharlayan::ChatFederation::Roster.advance(conversation, actor, published)
      membership = conversation.memberships.find_or_create_by!(account: actor)
      invitation.update!(state: :accepted)
      membership.previously_new_record?
    end

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    broadcast(conversation, 'chat.member_join', { conversation_id: conversation.id.to_s, account_id: actor.id.to_s }) if joined
    deliver_roster_after_join(conversation, actor)
    conversation
  end

  def refuse_accept(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil? || !conversation.owner_account&.local?
    return if conversation.memberships.exists?(account: actor)
    return unless conversation.invitations.exists?(invitee_account: actor)

    conversation.invitations.pending.find_by(invitee_account: actor)&.update!(state: :rejected)
    deliver_to_account(conversation.owner_account, Sharlayan::ChatFederation::Payload.remove(conversation, actor, actor: conversation.owner_account), actor)
  end

  def receive_reject(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?

    conversation.invitations.pending.find_by(invitee_account: actor)&.update!(state: :rejected)
    conversation.destroy_if_unused!
  end

  def receive_cancel(actor, room_uri:, invitee:, published: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Forbidden if conversation && conversation.owner_account_id != actor.id

    invitation = conversation&.invitations&.pending&.find_by(inviter_account: actor, invitee_account: invitee)
    if invitation.nil?
      membership = conversation&.memberships&.find_by(account: invitee)
      membership.nil? ? remember_invite_cancel(room_uri, actor, invitee, published) : withdraw_accepted_invite(conversation, membership, published)
      return
    end

    invitation.update!(state: :cancelled)
    Sharlayan::ChatFederation::Roster.advance(conversation, invitee, published)
    broadcast_to(invitee, 'chat.invitation', invitation, REST::ChatInvitationSerializer) if invitee.local?
    conversation.destroy_if_unused!
  end

  def receive_add(actor, room_uri:, account_uri:, published: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    raise Error, 'Unknown account' if account_uri.blank?

    account = account_from_uri(account_uri)
    raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat room member' if account.nil?

    raise Forbidden if account.local? && !conversation.memberships.exists?(account: account) && !conversation.invitations.exists?(invitee_account: account, state: :accepted)
    raise Forbidden if account.remote? && blocked_in_either_direction?(actor, account)

    # A local account only gets here having accepted and having neither left nor been removed since.
    joined = conversation.with_lock do
      next false unless Sharlayan::ChatFederation::Roster.applies?(conversation, account, published)

      Sharlayan::ChatFederation::Roster.advance(conversation, account, published)
      next false if conversation.memberships.exists?(account: account)

      ensure_group_capacity!(conversation)
      conversation.memberships.create!(account: account)
      true
    end
    return conversation unless joined

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    broadcast(conversation, 'chat.member_join', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    conversation
  end

  def receive_remove(actor, room_uri:, account_uri:, published: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?

    # Only the owner can name an account this server has not seen. Its later Add has to find this removal on record.
    by_owner = conversation.owner_account_id == actor.id
    account = account_from_uri(account_uri, fetch: by_owner)
    return if account.nil?
    raise Forbidden unless actor.id == account.id || by_owner

    outcome = conversation.with_lock do
      next :stale unless Sharlayan::ChatFederation::Roster.applies?(conversation, account, published, removal: true)

      Sharlayan::ChatFederation::Roster.advance(conversation, account, published)
      membership = conversation.memberships.find_by(account: account)
      next :absent if membership.nil? && actor.id == account.id
      next :owner if membership&.owner?

      membership&.destroy!
      forget_acceptance(conversation, account)
      :removed
    end
    return if %i(stale absent).include?(outcome)
    return tombstone_room(conversation, actor) if outcome == :owner

    broadcast_to(account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s }) if account.local?
    return unless ChatConversation.exists?(conversation.id)

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    relay_departure(conversation, account)
    schedule_abandoned_room_cleanup(conversation)
  end

  def receive_room_update(actor, room_uri:, title:, description: nil, archived: nil, updated: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    if conversation.nil?
      return if room_tombstoned?(room_uri)
      raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat room' if same_origin?(room_uri, actor.uri)

      raise Error, 'Unknown chat room'
    end
    raise Forbidden unless conversation.owner_account_id == actor.id

    applied = conversation.with_lock { apply_remote_room_state(conversation, title: title, description: description, archived: archived, updated: updated) }
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer) if applied
    conversation
  end

  def receive_room_delete(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return remember_room_tombstone(room_uri, actor, ttl: UNKNOWN_ROOM_TOMBSTONE_TTL) if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    tombstone_room(conversation, actor)
  end

  def update_remote_message(actor, message, text:, edited_at:)
    raise Forbidden unless message.account_id == actor.id
    raise Error, 'Deleted messages cannot be edited' if message.deleted?

    ensure_room_member!(message.chat_conversation, actor)
    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(actor, message.chat_conversation)

    message.with_lock do
      raise Error, 'Deleted messages cannot be edited' if message.deleted?
      return message if edited_at && message.edited_at && edited_at <= message.edited_at

      keep_previous_text(message, text)
      message.update!(text: text.to_s.strip.presence, edited_at: edited_at || Time.current)
    end
    broadcast(message.chat_conversation, 'chat.message_update', message, REST::ChatMessageSerializer)
    relay_update(message)
    message
  end

  def delete_remote_message(actor, message, activity: nil)
    raise Forbidden unless message.account_id == actor.id || (message.chat_conversation.chat_group? && message.chat_conversation.owner_account_id == actor.id)

    relay_activity(message.chat_conversation, actor, activity) if tombstone_message(message)
    message
  end

  def react_remote(actor, message, reaction, activity_id: nil, activity: nil)
    state = Sharlayan::ChatFederation::ReactionState.new(actor, message, reaction)
    return unless message.with_lock { remote_reaction_allowed?(actor, message, state, activity_id) }

    shortcode = ChatMessageReaction.shortcode_of(reaction)
    yield shortcode if shortcode && block_given?

    record = message.with_lock do
      next unless remote_reaction_allowed?(actor, message, state, activity_id)

      record = message.reactions.create_with(uri: activity_id).find_or_create_by!(account: actor, reaction: reaction)
      raise Error, 'Reaction activity could not be registered' unless state.add(activity_id)

      record
    end
    return unless record&.previously_new_record?

    broadcast(message.chat_conversation, 'chat.reaction', REST::ChatMessageReactionSerializer.new(record).as_json)
    relay_activity(message.chat_conversation, actor, activity)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def unreact_remote(actor, message, reaction, activity_id: nil, activity: nil)
    conversation = nil
    message.with_lock do
      conversation = message.chat_conversation
      ensure_conversation_writable!(conversation)
      # Someone who has left can still take back what they did while they were a member.
      remote_reaction_membership!(actor, conversation) unless message.reactions.exists?(account: actor, reaction: reaction) || room_participant?(conversation, actor)
      return unless Sharlayan::ChatFederation::ReactionState.new(actor, message, reaction).remove(activity_id)

      message.reactions.find_by(account: actor, reaction: reaction)&.destroy!
    end
    broadcast(conversation, 'chat.reaction_delete', { message_id: message.id.to_s, account_id: actor.id.to_s, reaction: reaction })
    relay_activity(conversation, actor, activity)
  end

  def remember_tombstone(uri, actor)
    raise Forbidden unless same_origin?(uri, actor.uri)

    redis.setex("chat_delete_upon_arrival:#{actor.id}:#{uri}", 6.hours.seconds, true)
  end

  def tombstone?(uri, actor)
    redis.exists?("chat_delete_upon_arrival:#{actor.id}:#{uri}")
  end

  def remember_room_tombstone(uri, actor, ttl: ROOM_TOMBSTONE_TTL)
    raise Forbidden unless same_origin?(uri, actor.uri)

    redis.setex(self.class.room_tombstone_key(uri), ttl.to_i, Time.current.iso8601(3))
  end

  def room_tombstoned?(uri)
    redis.exists?(self.class.room_tombstone_key(uri))
  end

  def room_deleted_at(uri)
    value = redis.get(self.class.room_tombstone_key(uri))
    value && Time.iso8601(value)
  end

  def message_of_deleted_room?(uri)
    redis.exists?(message_tombstone_key(uri))
  end

  def room_participant?(conversation, account)
    conversation.memberships.exists?(account: account) || conversation.roster_states.exists?(account: account)
  end

  def invite_cancelled?(room_uri, actor, invitee, published)
    cancelled_at = redis.get(invite_cancel_key(room_uri, actor, invitee))
    cancelled_at.present? && (published.nil? || published.to_f <= cancelled_at.to_f)
  end

  # What the room owner says about the members is applied to whoever it is newer for. Local accounts
  # only ever join by their own acceptance, so the list can take them out of a room but not put them in.
  def apply_roster(conversation, member_uris:, roster_at:)
    return if member_uris.size > MAX_REMOTE_ROOM_MEMBERS

    listed = member_uris.uniq.filter_map { |uri| roster_account(uri) }
    joined, left = conversation.with_lock { merge_roster(conversation, listed, roster_at) }

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer) if joined.any? || left.any?
    joined.each { |account| broadcast(conversation, 'chat.member_join', { conversation_id: conversation.id.to_s, account_id: account.id.to_s }) }
    left.each do |account|
      broadcast_to(account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s }) if account.local?
      broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    end
    schedule_abandoned_room_cleanup(conversation) if left.any?
  end

  private

  def roster_account(uri)
    account_from_uri(uri)
  rescue *Mastodon::HTTP_CONNECTION_ERRORS, Mastodon::UnexpectedResponseError, Mastodon::RaceConditionError => e
    Rails.logger.info("Could not resolve chat room member #{uri}: #{e.message}")
    nil
  end

  def merge_roster(conversation, listed, roster_at)
    memberships = conversation.memberships.includes(:account).index_by(&:account_id)
    known_at = conversation.roster_states.pluck(:account_id, :last_roster_at).to_h

    joined = []
    listed.each do |account|
      next if account.id == conversation.owner_account_id || known_at[account.id]&.>=(roster_at)

      next unless memberships.key?(account.id) || roster_can_add?(conversation, account)

      Sharlayan::ChatFederation::Roster.advance(conversation, account, roster_at)
      next if memberships.key?(account.id)

      conversation.memberships.create!(account: account)
      joined << account
    end

    listed_ids = listed.to_set(&:id)
    left = memberships.values.filter_map do |membership|
      next if membership.owner? || listed_ids.include?(membership.account_id) || known_at[membership.account_id]&.>=(roster_at)
      next if awaiting_acceptance?(conversation, membership.account, roster_at)

      membership.destroy!
      Sharlayan::ChatFederation::Roster.advance(conversation, membership.account, roster_at)
      membership.account
    end

    [joined, left]
  end

  # The owner may have yet to hear of an acceptance this server has only just sent.
  def awaiting_acceptance?(conversation, account, roster_at)
    account.local? && conversation.invitations.exists?(invitee_account: account, state: :accepted, updated_at: [roster_at, ACCEPT_DELIVERY_GRACE.ago].min..)
  end

  # An acceptance can bring someone back only until they have left or been removed.
  def forget_acceptance(conversation, account)
    conversation.invitations.where(invitee_account: account, state: :accepted).find_each { |invitation| invitation.update!(state: :cancelled) }
  end

  def roster_can_add?(conversation, account)
    return false if account.local? || account.suspended? || blocked_in_either_direction?(conversation.owner_account, account)

    conversation.memberships.count < MAX_REMOTE_ROOM_MEMBERS
  end

  def withdraw_accepted_invite(conversation, membership, published)
    account = membership.account
    withdrawn = conversation.with_lock do
      next false if published.nil? || membership.owner? || !Sharlayan::ChatFederation::Roster.applies?(conversation, account, published)

      Sharlayan::ChatFederation::Roster.advance(conversation, account, published)
      membership.destroy!
      forget_acceptance(conversation, account)
      true
    end
    return unless withdrawn

    broadcast_to(account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s }) if account.local?
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    conversation.destroy_if_unused!
  end

  def tombstone_room(conversation, actor)
    message_uris = conversation.messages.where.not(uri: nil).limit(MAX_TOMBSTONED_ROOM_MESSAGES).pluck(:uri)
    room_uri = conversation.uri

    destroy_and_announce(conversation)
    remember_room_tombstone(room_uri, actor)
    redis.pipelined { |pipeline| message_uris.each { |uri| pipeline.setex(message_tombstone_key(uri), ROOM_TOMBSTONE_TTL.to_i, '1') } }
  end

  def message_tombstone_key(uri)
    "chat_room_message_tombstone:#{Digest::SHA256.hexdigest(uri.to_s)}"
  end

  def ensure_room_member!(conversation, actor)
    return if conversation.memberships.exists?(account: actor)
    raise Forbidden unless conversation.chat_group? && actor.remote?

    if conversation.local?
      raise Forbidden unless conversation.invitations.pending.exists?(invitee_account: actor)
    else
      Sharlayan::ChatFederation::Roster.request_sync(conversation, actor.id)
    end

    raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat membership'
  end

  def relay_update(message)
    conversation = message.chat_conversation
    return unless conversation.chat_group? && conversation.owner_account&.local? && message.account.remote? && Setting.chat_federation_enabled

    Sharlayan::ChatFederation::Delivery.call(
      actor: conversation.owner_account,
      conversation: conversation,
      payload: Sharlayan::ChatFederation::Payload.announce_update(message),
      except_account_id: message.account_id,
      except_domain: message.account.domain
    )
  end

  def relay_activity(conversation, actor, activity)
    return if activity.nil? || !activity['id'].is_a?(String)
    return unless conversation.chat_group? && conversation.owner_account&.local? && actor.remote? && Setting.chat_federation_enabled

    Sharlayan::ChatFederation::Delivery.call(
      actor: conversation.owner_account,
      conversation: conversation,
      payload: Sharlayan::ChatFederation::Payload.announce_activity(conversation, activity),
      except_account_id: actor.id,
      except_domain: actor.domain
    )
  end

  def invite_cancel_key(room_uri, actor, invitee)
    "chat_invite_cancelled:#{actor.id}:#{invitee.id}:#{Digest::SHA256.hexdigest(room_uri.to_s)}"
  end

  def remember_invite_cancel(room_uri, actor, invitee, published)
    return unless same_origin?(room_uri, actor.uri)

    redis.setex(invite_cancel_key(room_uri, actor, invitee), INVITE_CANCEL_TTL.to_i, (published || Time.current).to_f.to_s)
  end

  def apply_remote_room_state(conversation, title:, description:, archived:, updated:)
    return false if updated && conversation.state_updated_at && updated < conversation.state_updated_at

    conversation.title = title.to_s[0, MAX_ROOM_TITLE_LENGTH] if title.is_a?(String) && title.present?
    conversation.description = description[0, MAX_ROOM_DESCRIPTION_LENGTH] if description.is_a?(String)
    conversation.archived_at = archived ? (conversation.archived_at || Time.current) : nil if [true, false].include?(archived)
    conversation.state_updated_at = updated if updated
    conversation.save!
    true
  end

  def save_room_state!(conversation)
    return unless conversation.changed?

    previous = conversation.state_updated_at || conversation.updated_at
    conversation.state_updated_at = [Time.current, previous + Rational(1, 1000)].max
    conversation.save!
  end

  def acknowledge_repeated_invite(conversation, actor, invitee)
    invitation = conversation.invitations.where(invitee_account: invitee).order(:id).last ||
                 conversation.invitations.create!(inviter_account: actor, invitee_account: invitee, state: :accepted)
    deliver_to_account(invitee, Sharlayan::ChatFederation::Payload.accept(invitation), actor)
    invitation
  end

  def tombstone_message(message)
    media_attachments = message.with_lock do
      next if message.deleted?

      media = message.media_attachments.to_a
      message.reactions.destroy_all
      message.chat_message_media_attachments.destroy_all
      message.edits.delete_all
      message.update!(text: nil, deleted_at: Time.current)
      media
    end
    return false if media_attachments.nil?

    media_attachments.each { |media| media.destroy! if media.removable_with_chat_message? }
    broadcast(message.chat_conversation, 'chat.message_delete', { id: message.id.to_s, conversation_id: message.chat_conversation_id.to_s })
    true
  end

  def remote_reaction_allowed?(actor, message, state, activity_id)
    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(actor, message.chat_conversation)
    raise Error, 'Deleted messages cannot receive reactions' if message.deleted?
    raise Forbidden if message.account_id == actor.id

    remote_reaction_membership!(actor, message.chat_conversation)
    state.accepts?(activity_id)
  end

  def relay_to_room(conversation, message)
    return unless message&.previously_new_record? && conversation.owner_account&.local? && Setting.chat_federation_enabled

    Sharlayan::ChatFederation::Delivery.call(
      actor: conversation.owner_account,
      conversation: conversation,
      payload: Sharlayan::ChatFederation::Payload.announce_message(message),
      except_account_id: message.account_id,
      except_domain: message.account.domain
    )
  end

  def schedule_abandoned_room_cleanup(conversation)
    return if conversation.local? || conversation.accounts.local.exists?

    ChatConversationCleanupWorker.perform_in(ChatConversationCleanupWorker::CLEANUP_DELAY, conversation.id)
  end

  def refresh_remote_account(account)
    return unless account.remote? && account.possibly_stale?

    ActivityPub::FetchRemoteAccountService.new.call(account.uri)
    account.reload
  rescue *Mastodon::HTTP_CONNECTION_ERRORS, Mastodon::UnexpectedResponseError, Mastodon::RaceConditionError => e
    Rails.logger.info("Could not refresh #{account.uri} before starting a chat: #{e.message}")
  end

  def remote_reaction_membership!(actor, conversation)
    ensure_room_member!(conversation, actor)
  end

  def create_remote_message(conversation, actor, uri:, text:, created_at:, attachments:, edited_at: nil, reply_to_uri: nil)
    return nil if tombstone?(uri, actor)

    raise Forbidden unless conversation.memberships.exists?(account: actor)

    ensure_conversation_writable!(conversation)
    ensure_direct_participants_not_blocked!(actor, conversation)

    reply_to = conversation.messages.find_by(uri: reply_to_uri) if reply_to_uri.present?

    message = nil
    media = []
    conversation.with_lock do
      existing = ChatMessage.find_by(uri: uri)
      if existing
        raise Forbidden unless existing.account_id == actor.id && existing.chat_conversation_id == conversation.id

        return edited_at ? update_remote_message(actor, existing, text: text, edited_at: edited_at) : existing
      end

      message = conversation.messages.build(
        account: actor,
        uri: uri,
        reply_to: reply_to,
        text: text.to_s.strip.presence,
        edited_at: edited_at,
        created_at: created_at || Time.current
      )
      media = attachments.filter_map { |attachment| incoming_media(actor, attachment) }
      raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat attachments' if media.empty? && attachments.any? && text.blank?

      message.pending_media_attachments = media
      message.save!
      media.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }
      conversation.update!(last_message: message)
    end
    download_incoming_media(actor, media)
    broadcast(conversation, 'chat.message', message, REST::ChatMessageSerializer)
    notify_members(conversation, message)
    message
  end

  def incoming_media(actor, document)
    url = document['url']
    url = url.first if url.is_a?(Array)
    url = url['href'] || url['url'] if url.is_a?(Hash)
    return unless http_url?(url)

    parser = ActivityPub::Parser::MediaAttachmentParser.new(document)
    content_type = supported_media_content_type(parser.file_content_type)

    MediaAttachment.create!(
      account: actor,
      remote_url: url.to_s,
      file_content_type: content_type,
      type: declared_media_type(content_type),
      description: parser.description,
      blurhash: parser.blurhash
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.info("Could not store a chat attachment from #{actor.uri}: #{e.message}")
    nil
  end

  def supported_media_content_type(content_type)
    content_type if (MediaAttachment::VIDEO_MIME_TYPES + MediaAttachment::AUDIO_MIME_TYPES + MediaAttachment::IMAGE_MIME_TYPES).include?(content_type)
  end

  def declared_media_type(content_type)
    return :video if MediaAttachment::VIDEO_MIME_TYPES.include?(content_type)
    return :audio if MediaAttachment::AUDIO_MIME_TYPES.include?(content_type)
    return :image if MediaAttachment::IMAGE_MIME_TYPES.include?(content_type)

    :unknown
  end

  def download_incoming_media(actor, media)
    return if media.empty? || DomainBlock.reject_media?(actor.domain)

    ActiveRecord.after_all_transactions_commit do
      media.each { |attachment| RedownloadMediaWorker.perform_async(attachment.id) }
    end
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
      relay_departure(conversation, membership.account)
    else
      destroy_and_announce(conversation)
    end
  end

  # A server let back in after a domain suspension can still accept an old invitation, and only the
  # record of that invitation earns the Remove that clears its copy of the room.
  def purge_invitations(account)
    ChatInvitation.where(inviter_account: account).in_batches.delete_all

    received = ChatInvitation.where(invitee_account: account)
    if account.remote?
      owned_here = received.where(chat_conversation_id: ChatConversation.local_only.select(:id))
      owned_here.pending.in_batches.update_all(state: ChatInvitation.states[:cancelled])
      received = received.where.not(id: owned_here.select(:id))
    end
    received.in_batches.delete_all
  end

  def purge_messages(account)
    conversation_ids = account.chat_messages.distinct.pluck(:chat_conversation_id)
    account.chat_messages.in_batches.destroy_all

    ChatConversation.where(id: conversation_ids, last_message_id: nil).find_each do |conversation|
      conversation.update!(last_message: conversation.messages.first)
    end
  end

  def relay_departure(conversation, account)
    owner = conversation.owner_account
    return unless owner&.local? && account.remote?

    deliver_to_conversation(owner, conversation, Sharlayan::ChatFederation::Payload.remove(conversation, account, actor: owner))
  end

  def deliver_roster_after_join(conversation, joined_account)
    owner = conversation.owner_account
    return if owner.nil?

    members = conversation.accounts.to_a
    members.select { |member| member.remote? && member.id != joined_account.id && member.id != owner.id }.uniq(&:preferred_inbox_url).each do |member|
      deliver_to_account(owner, Sharlayan::ChatFederation::Payload.add(conversation, joined_account), member)
    end
    if joined_account.remote?
      members.each do |member|
        next if member.id == joined_account.id || member.id == owner.id

        payload = Sharlayan::ChatFederation::Payload.add(conversation, member)
        deliver_to_account(owner, payload, joined_account)
      end
    end
  end

  def deliver_to_conversation(actor, conversation, payload, message: nil)
    return unless Setting.chat_federation_enabled

    ActiveRecord.after_all_transactions_commit do
      Sharlayan::ChatFederation::Delivery.call(actor: actor, conversation: conversation, payload: payload, except_account_id: actor.id, message: message)
    end
  end

  def deliver_room_state(actor, conversation, payload)
    return unless Setting.chat_federation_enabled

    ActiveRecord.after_all_transactions_commit do
      Sharlayan::ChatFederation::Delivery.call(actor: actor, conversation: conversation, payload: payload, except_account_id: actor.id, include_pending_invitees: true)
    end
  end

  def deliver_to_account(actor, payload, account)
    return unless Setting.chat_federation_enabled
    return if account.preferred_inbox_url.blank?
    return if account.suspended? && Sharlayan::ChatFederation::Delivery::RETRACTION_TYPES.exclude?(payload['type'])

    ActiveRecord.after_all_transactions_commit do
      ActivityPub::DeliveryWorker.perform_async(payload.to_json, actor.id, account.preferred_inbox_url)
    end
  end

  def account_from_uri(uri, fetch: true)
    return if uri.blank?

    account = ActivityPub::TagManager.instance.uri_to_resource(uri, Account)
    account ||= ActivityPub::FetchRemoteAccountService.new.call(uri) if fetch && !ActivityPub::TagManager.instance.local_uri?(uri)
    account
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def same_origin?(first, second)
    return false unless first.is_a?(String) && second.is_a?(String)

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

  # Where deleting only hides a message, an edit must not be a way to get rid of what it said.
  def keep_previous_text(message, text)
    return unless RoleplayModeHelper.roleplay_mode? || Setting.chat_soft_delete_enabled
    return if message.text.blank? || message.text == text.to_s.strip

    message.edits.create!(text: message.text)
  end

  def hide_instead_of_delete?(message)
    !message.deletes_for_everyone?
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

    create_direct_record(account, other, key)
  end

  def create_group(account, participants, title, description)
    invitees = participants.reject { |participant| participant.id == account.id }
    raise Error, 'The group has too many members' if invitees.size + 1 > Setting.chat_max_group_members
    raise Forbidden if invitees.any? { |participant| blocked_in_either_direction?(account, participant) || silenced_for?(account, participant) }
    raise Forbidden unless invitees.all? { |participant| accepts_group_invites?(participant) }

    conversation = ChatConversation.transaction do
      record = ChatConversation.create!(conversation_type: :group, owner_account: account, title: title, description: description, state_updated_at: Time.current)
      record.update!(uri: local_room_uri(record))
      record.memberships.create!(account: account, role: :owner)
      invitees.each do |participant|
        record.invitations.create!(inviter_account: account, invitee_account: participant)
      end
      record
    end

    conversation.invitations.pending.includes(:invitee_account).find_each do |invitation|
      if invitation.invitee_account.local?
        broadcast_to(invitation.invitee_account, 'chat.invitation', invitation, REST::ChatInvitationSerializer)
      else
        deliver_to_account(account, Sharlayan::ChatFederation::Payload.invite(conversation, invitation.invitee_account), invitation.invitee_account)
      end
    end
    conversation
  end

  def create_direct_record(account, other, key)
    ChatConversation.transaction(requires_new: true) do
      conversation = ChatConversation.create!(conversation_type: :direct, direct_key: key)
      conversation.memberships.create!([{ account: account }, { account: other }])
      conversation
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    ChatConversation.find_by(direct_key: key) || raise
  end

  def membership!(account, conversation)
    conversation.memberships.find_by!(account: account)
  rescue ActiveRecord::RecordNotFound
    raise Forbidden
  end

  def ensure_conversation_writable!(conversation)
    raise Error, 'Archived conversations are read-only' if conversation.archived?
  end

  def ensure_federation_available!(conversation)
    raise Error, 'Chat federation is disabled' if !Setting.chat_federation_enabled && conversation.remote?
  end

  def ensure_direct_participants_not_blocked!(account, conversation)
    return unless conversation.chat_direct?

    other_accounts = conversation.accounts.where.not(id: account.id)
    raise Forbidden if other_accounts.any? { |other_account| blocked_in_either_direction?(account, other_account) }
  end

  def owner_refused?(owner)
    owner.present? && (owner.suspended? || domain_not_allowed?(owner.domain))
  end

  def ensure_direct_recipient_not_suspended!(account, conversation)
    return unless conversation.chat_direct?

    raise Forbidden if conversation.accounts.where.not(id: account.id).where.not(suspended_at: nil).exists?
  end

  def ensure_group_capacity!(conversation, include_pending: false)
    size = conversation.memberships.count
    size += conversation.invitations.pending.count if include_pending
    raise Error, 'The group has too many members' if size >= (conversation.local? ? Setting.chat_max_group_members : MAX_REMOTE_ROOM_MEMBERS)
  end

  def blocked_in_either_direction?(first_account, second_account)
    first_account.blocking_or_domain_blocking?(second_account) || second_account.blocking_or_domain_blocking?(first_account)
  end

  def media_attachments(account, ids)
    normalized_ids = ids.map(&:to_s).uniq
    raise Error, "A chat message can contain up to #{Setting.chat_max_attachments} attachments" if normalized_ids.size > Setting.chat_max_attachments

    attachments = MediaAttachment.unattached.where(id: normalized_ids, account: account).sort_by { |media| normalized_ids.index(media.id.to_s) }
    raise Error, 'One or more media attachments were not found' unless attachments.size == normalized_ids.size
    raise Error, 'One or more media attachments are still being processed' if attachments.any?(&:not_processed?)

    attachments
  end

  def accepts_group_invites?(account)
    account.local? ? account.user&.settings&.[](:chat_allow_group_invites) : account.can_chat
  end

  def silenced_for?(sender, recipient)
    sender.silenced? && !recipient.following?(sender)
  end

  def direct_chat_allowed?(sender, recipient)
    return false if blocked_in_either_direction?(sender, recipient) || silenced_for?(sender, recipient)

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
    rendered = Sharlayan::ChatBroadcastPayload.new(object, serializer)
    conversation.memberships.joins(:account).merge(Account.local).includes(:account).find_each do |membership|
      broadcast_to(membership.account, event, rendered.for(membership.account))
    end
  end

  def broadcast_to(account, event, object, serializer = nil)
    payload = serializer ? serializer.new(object, current_account: account).as_json : object
    ActiveRecord.after_all_transactions_commit do
      redis.publish("timeline:#{account.id}", JSON.generate(event: event, payload: JSON.generate(payload.as_json)))
      MisskeyCompat::ChatStreaming.broadcast(redis, account, event, payload)
    end
  end

  def notify_members(conversation, message)
    rendered = Sharlayan::ChatBroadcastPayload.new(message, REST::ChatMessageSerializer)
    conversation.memberships.includes(account: :user).where.not(account_id: message.account_id).find_each do |membership|
      next if membership.muted? || !membership.account.user&.settings&.[](:chat_notifications)

      broadcast_to(membership.account, 'chat.notification', rendered.for(membership.account))
    end
  end
end
