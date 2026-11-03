# frozen_string_literal: true

class Sharlayan::ChatService
  include Redisable

  class Error < StandardError; end
  class Forbidden < Error; end

  MAX_PENDING_REMOTE_ROOMS = 100
  # A room's own server sets its size. This only bounds what one peer can make us store.
  MAX_REMOTE_ROOM_MEMBERS = 1000
  MAX_ROOM_TITLE_LENGTH = 256
  MAX_ROOM_DESCRIPTION_LENGTH = 2048
  INVITE_CANCEL_TTL = 6.hours

  def create_conversation(account, type:, account_ids: [], title: nil, description: nil)
    raise Error, 'Unknown chat type' unless %w(direct group).include?(type.to_s)

    requested_ids = account_ids.map(&:to_s).uniq
    requested_participant_ids = requested_ids.reject { |id| id == account.id.to_s }
    participant_limit = type.to_s == 'direct' ? 1 : Setting.chat_max_group_members - 1
    raise Error, 'The group has too many members' if requested_participant_ids.size > participant_limit

    participants = Account.without_suspended.where(id: requested_ids).to_a
    raise Error, 'One or more chat participants were not found' unless participants.size == requested_ids.size
    raise Error, 'Chat federation is disabled' if participants.any?(&:remote?) && !Setting.chat_federation_enabled

    participants.each { |participant| refresh_remote_account(participant) }

    type.to_s == 'direct' ? create_direct(account, participants) : create_group(account, participants, title, description)
  end

  def create_message(account, conversation, text:, reply_to_id: nil, media_ids: [])
    membership = membership!(account, conversation)
    ensure_conversation_writable!(conversation)
    ensure_federation_available!(conversation)
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
    ensure_federation_available!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(account, message.chat_conversation)
    message.with_lock do
      raise Error, 'Deleted messages cannot be edited' if message.deleted?

      # JavaScript peers compare millisecond versions. Reload under the lock so
      # concurrent edits and edits within one clock tick still advance the version.
      edited_at = Time.current
      edited_at = [edited_at, message.edited_at + Rational(1, 1000)].max if message.edited_at
      message.update!(text: text.to_s.strip.presence, edited_at: edited_at)
    end
    broadcast(message.chat_conversation, 'chat.message_update', message, REST::ChatMessageSerializer)
    deliver_to_conversation(account, message.chat_conversation, Sharlayan::ChatFederation::Payload.update(message))
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
    record = message.with_lock do
      raise Error, 'Deleted messages cannot receive reactions' if message.deleted?

      # Each activity ID stands for one reaction, so repeating a reaction must not mint another.
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
    raise Forbidden if blocked_in_either_direction?(invitation.inviter_account, account)

    conversation = invitation.chat_conversation
    joined = conversation.with_lock do
      invitation.lock!
      raise Forbidden unless invitation.pending?

      ensure_group_capacity!(conversation) unless conversation.memberships.exists?(account: account)
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

    # Removing one side of a direct chat would delete it for the other side too.
    raise Error, 'Only group chats can be left' unless conversation.chat_group?

    deliver_to_conversation(account, conversation, Sharlayan::ChatFederation::Payload.remove(conversation, account))
    membership.destroy!
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
    recipients.uniq(&:inbox_url).each { |recipient| deliver_to_account(account, payload, recipient) }
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

  # Removes every trace of an account's chat activity. DeleteAccountService keeps
  # the account record by default, so `dependent: :destroy` alone is not enough.
  def purge_account(account, federate: true)
    federate &&= account.local?

    account.owned_chat_conversations.find_each do |conversation|
      deliver_room_state(account, conversation, Sharlayan::ChatFederation::Payload.delete_room(conversation)) if federate && conversation.chat_group?
      destroy_and_announce(conversation)
    end
    account.chat_memberships.includes(:chat_conversation).find_each { |membership| purge_membership(membership, federate: federate) }
    account.chat_message_reactions.in_batches.delete_all
    purge_messages(account)
    ChatInvitation.where(invitee_account: account).or(ChatInvitation.where(inviter_account: account)).in_batches.delete_all
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

      # As with local chats, the policy only gates starting a conversation: it must not
      # drop replies to a chat the recipient started. create_remote_message checks blocks.
      if conversation.nil?
        raise Forbidden unless direct_chat_allowed?(actor, recipient)

        conversation = create_direct_record(recipient, actor, key)
      end

      create_remote_message(conversation, actor, uri: uri, text: text, created_at: created_at, edited_at: edited_at, attachments: attachments, reply_to_uri: reply_to_uri)
    end
  end

  def receive_group_message(actor, room_uri:, uri:, text:, created_at: nil, edited_at: nil, attachments: [], reply_to_uri: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    # Independent delivery queues can put Create ahead of Invite, Accept or Add.
    # Let the ingress worker retry; membership still has to be granted by the owner.
    raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat room' if conversation.nil?

    ensure_conversation_writable!(conversation)
    raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat membership' unless conversation.memberships.exists?(account: actor)

    unless conversation.accounts.local.exists?
      raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat membership' if conversation.invitations.pending.joins(:invitee_account).merge(Account.local).exists?

      raise Forbidden
    end

    message = create_remote_message(conversation, actor, uri: uri, text: text, created_at: created_at, edited_at: edited_at, attachments: attachments, reply_to_uri: reply_to_uri)
    relay_to_room(conversation, message)
    message
  end

  def receive_invite(invitee, actor, room_uri:, title:, description: nil, archived: nil, updated: nil)
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

      # Redelivery of an Invite the member already answered must not ask them again.
      next acknowledge_repeated_invite(conversation, actor, invitee) if conversation.memberships.exists?(account: invitee)

      ensure_group_capacity!(conversation)
      conversation.invitations.pending.find_by(invitee_account: invitee) ||
        conversation.invitations.create!(inviter_account: actor, invitee_account: invitee)
    end
    ChatConversationCleanupWorker.perform_in(ChatConversationCleanupWorker::CLEANUP_DELAY, invitation.chat_conversation_id) if actor.remote?
    broadcast_to(invitee, 'chat.invitation', invitation, REST::ChatInvitationSerializer) if invitation.pending?
    # Serializing loaded the room and its roster, which later activities change.
    invitation.reload
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def receive_accept(actor, room_uri:)
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
      membership = conversation.memberships.find_or_create_by!(account: actor)
      invitation.update!(state: :accepted)
      membership.previously_new_record?
    end

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    broadcast(conversation, 'chat.member_join', { conversation_id: conversation.id.to_s, account_id: actor.id.to_s }) if joined
    deliver_roster_after_join(conversation, actor)
    conversation
  end

  # The invitee's server joined the room before sending Accept, so it has to hear when
  # the owner's server cannot honor it. A redelivered Accept from a member is not a refusal.
  def refuse_accept(actor, room_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil? || !conversation.owner_account&.local?
    return if conversation.memberships.exists?(account: actor)

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
      remember_invite_cancel(room_uri, actor, invitee, published)
      return
    end

    invitation.update!(state: :cancelled)
    broadcast_to(invitee, 'chat.invitation', invitation, REST::ChatInvitationSerializer) if invitee.local?
    conversation.destroy_if_unused!
  end

  def receive_add(actor, room_uri:, account_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    raise Error, 'Unknown chat room' if conversation.nil?
    raise Forbidden unless conversation.owner_account_id == actor.id

    # The owner decides who is in the room, and an archive may have overtaken this Add.
    raise Error, 'Unknown account' if account_uri.blank?

    account = account_from_uri(account_uri)
    # The account may be unreachable for a moment. Losing the Add would strand that member.
    raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat room member' if account.nil?

    if account.local?
      raise Forbidden unless conversation.memberships.exists?(account: account)

      return conversation
    end

    raise Forbidden if blocked_in_either_direction?(actor, account)

    joined = conversation.with_lock do
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

  def receive_remove(actor, room_uri:, account_uri:)
    conversation = ChatConversation.find_by(uri: room_uri)
    return if conversation.nil?

    account = account_from_uri(account_uri, fetch: false)
    return if account.nil?
    raise Forbidden unless actor.id == account.id || conversation.owner_account_id == actor.id

    broadcast_to(account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s }) if account.local?
    conversation.memberships.find_by(account: account)&.destroy!
    # Removing the owner's own membership removes the room.
    return unless ChatConversation.exists?(conversation.id)

    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
    relay_departure(conversation, account)
    schedule_abandoned_room_cleanup(conversation)
  end

  def receive_room_update(actor, room_uri:, title:, description: nil, archived: nil, updated: nil)
    conversation = ChatConversation.find_by(uri: room_uri)
    if conversation.nil?
      return if room_tombstoned?(room_uri, actor)
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

    tombstone_message(message)
    message
  end

  def react_remote(actor, message, reaction, activity_id: nil)
    state = Sharlayan::ChatFederation::ReactionState.new(actor, message, reaction)
    return unless message.with_lock { remote_reaction_allowed?(actor, message, state, activity_id) }

    # Imported only after authorization and replay checks, including on ingress retries, and
    # outside the lock because it downloads from a server the reactor controls.
    shortcode = ChatMessageReaction.shortcode_of(reaction)
    yield shortcode if shortcode && block_given?

    record = message.with_lock do
      next unless remote_reaction_allowed?(actor, message, state, activity_id)

      record = message.reactions.find_or_create_by!(account: actor, reaction: reaction)
      raise Error, 'Reaction activity could not be registered' unless state.add(activity_id)

      record
    end
    return unless record&.previously_new_record?

    broadcast(message.chat_conversation, 'chat.reaction', REST::ChatMessageReactionSerializer.new(record).as_json)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def unreact_remote(actor, message, reaction, activity_id: nil)
    message.with_lock do
      ensure_conversation_writable!(message.chat_conversation)
      remote_reaction_membership!(actor, message.chat_conversation)
      return unless Sharlayan::ChatFederation::ReactionState.new(actor, message, reaction).remove(activity_id)

      message.reactions.find_by(account: actor, reaction: reaction)&.destroy!
    end
    broadcast(message.chat_conversation, 'chat.reaction_delete', { message_id: message.id.to_s, account_id: actor.id.to_s, reaction: reaction })
  end

  def remember_tombstone(uri, actor)
    raise Forbidden unless same_origin?(uri, actor.uri)

    redis.setex("chat_delete_upon_arrival:#{actor.id}:#{uri}", 6.hours.seconds, true)
  end

  def tombstone?(uri, actor)
    redis.exists?("chat_delete_upon_arrival:#{actor.id}:#{uri}")
  end

  def remember_room_tombstone(uri, actor)
    raise Forbidden unless same_origin?(uri, actor.uri)

    redis.setex("chat_room_delete_upon_arrival:#{actor.id}:#{uri}", 6.hours.seconds, true)
  end

  def room_tombstoned?(uri, actor)
    redis.exists?("chat_room_delete_upon_arrival:#{actor.id}:#{uri}")
  end

  # An Undo can overtake its Invite. A later re-invitation still has to get through.
  def invite_cancelled?(room_uri, actor, invitee, published)
    cancelled_at = redis.get(invite_cancel_key(room_uri, actor, invitee))
    cancelled_at.present? && (published.nil? || published.to_f <= cancelled_at.to_f)
  end

  private

  def invite_cancel_key(room_uri, actor, invitee)
    "chat_invite_cancelled:#{actor.id}:#{invitee.id}:#{Digest::SHA256.hexdigest(room_uri.to_s)}"
  end

  def remember_invite_cancel(room_uri, actor, invitee, published)
    return unless same_origin?(room_uri, actor.uri)

    redis.setex(invite_cancel_key(room_uri, actor, invitee), INVITE_CANCEL_TTL.to_i, (published || Time.current).to_f.to_s)
  end

  # Returns false for a snapshot older than what has been applied. Call while holding the room lock.
  def apply_remote_room_state(conversation, title:, description:, archived:, updated:)
    return false if updated && conversation.state_updated_at && updated < conversation.state_updated_at

    conversation.title = title.to_s[0, MAX_ROOM_TITLE_LENGTH] if title.is_a?(String) && title.present?
    conversation.description = description[0, MAX_ROOM_DESCRIPTION_LENGTH] if description.is_a?(String)
    conversation.archived_at = archived ? (conversation.archived_at || Time.current) : nil if [true, false].include?(archived)
    conversation.state_updated_at = updated if updated
    conversation.save!
    true
  end

  # Peers compare versions at millisecond precision, so each change has to move past the last one.
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

  # Members deliver to the people they know about, and a roster change can still be in flight,
  # so the owner's server passes each new message on. Receivers ignore one they already have.
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

  # History stays for a later invitation, but not forever once nobody here can read it.
  def schedule_abandoned_room_cleanup(conversation)
    return if conversation.local? || conversation.accounts.local.exists?

    ChatConversationCleanupWorker.perform_in(ChatConversationCleanupWorker::CLEANUP_DELAY, conversation.id)
  end

  # Stale copies of an actor say nothing reliable about whether its server can chat.
  def refresh_remote_account(account)
    return unless account.remote? && account.possibly_stale?

    ActivityPub::FetchRemoteAccountService.new.call(account.uri)
    account.reload
  rescue *Mastodon::HTTP_CONNECTION_ERRORS, Mastodon::UnexpectedResponseError, Mastodon::RaceConditionError => e
    Rails.logger.info("Could not refresh #{account.uri} before starting a chat: #{e.message}")
  end

  def remote_reaction_membership!(actor, conversation)
    membership = conversation.memberships.find_by(account: actor)
    return membership if membership

    raise Forbidden unless actor.remote? && conversation.chat_group?

    raise Sharlayan::ChatFederation::DependencyNotReadyError, 'Waiting for chat membership'
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
      # Recheck after serializing creation: an Update may have seen no message
      # before another ingress worker committed Create (or a newer Update).
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
  end

  # An unsupported declaration must not lose the message. The download validates the real file.
  def supported_media_content_type(content_type)
    content_type if (MediaAttachment::VIDEO_MIME_TYPES + MediaAttachment::AUDIO_MIME_TYPES + MediaAttachment::IMAGE_MIME_TYPES).include?(content_type)
  end

  # Clients pick the player from the type before the file is here. Downloading replaces it.
  def declared_media_type(content_type)
    return :video if MediaAttachment::VIDEO_MIME_TYPES.include?(content_type)
    return :audio if MediaAttachment::AUDIO_MIME_TYPES.include?(content_type)
    return :image if MediaAttachment::IMAGE_MIME_TYPES.include?(content_type)

    :unknown
  end

  # The caller may hold a transaction, and the worker gives up on a record it cannot find yet.
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

    ActiveRecord.after_all_transactions_commit do
      Sharlayan::ChatFederation::Delivery.call(actor: actor, conversation: conversation, payload: payload, except_account_id: actor.id)
    end
  end

  # Invitees have not joined, but what they would be joining has changed.
  def deliver_room_state(actor, conversation, payload)
    return unless Setting.chat_federation_enabled

    ActiveRecord.after_all_transactions_commit do
      Sharlayan::ChatFederation::Delivery.call(actor: actor, conversation: conversation, payload: payload, except_account_id: actor.id, include_pending_invitees: true)
    end
  end

  def deliver_to_account(actor, payload, account)
    return unless Setting.chat_federation_enabled
    return if account.inbox_url.blank?

    # A caller's transaction can still roll back, and peers must not hear about what never happened.
    ActiveRecord.after_all_transactions_commit do
      ActivityPub::DeliveryWorker.perform_async(payload.to_json, actor.id, account.inbox_url)
    end
  end

  def account_from_uri(uri, fetch: true)
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

    create_direct_record(account, other, key)
  end

  def create_group(account, participants, title, description)
    invitees = participants.reject { |participant| participant.id == account.id }
    raise Error, 'The group has too many members' if invitees.size + 1 > Setting.chat_max_group_members
    raise Forbidden if invitees.any? { |participant| blocked_in_either_direction?(account, participant) }
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

  # The savepoint keeps a caller's transaction usable when another request created it first.
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

  # Without this, a message would be stored and reported as sent but never reach the other side.
  def ensure_federation_available!(conversation)
    raise Error, 'Chat federation is disabled' if !Setting.chat_federation_enabled && conversation.remote?
  end

  def ensure_direct_participants_not_blocked!(account, conversation)
    return unless conversation.chat_direct?

    other_accounts = conversation.accounts.where.not(id: account.id)
    raise Forbidden if other_accounts.any? { |other_account| blocked_in_either_direction?(account, other_account) }
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

    attachments = MediaAttachment.unattached.where(id: normalized_ids, account: account).to_a
    raise Error, 'One or more media attachments were not found' unless attachments.size == normalized_ids.size
    raise Error, 'One or more media attachments are still being processed' if attachments.any?(&:not_processed?)

    attachments
  end

  def accepts_group_invites?(account)
    account.local? ? account.user&.settings&.[](:chat_allow_group_invites) : account.can_chat
  end

  # Moderators limited this account, so it reaches only the people who chose to follow it.
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
    conversation.memberships.joins(:account).merge(Account.local).includes(:account).find_each do |membership|
      payload = serializer ? serializer.new(object, current_account: membership.account).as_json : object
      broadcast_to(membership.account, event, payload)
    end
  end

  def broadcast_to(account, event, object, serializer = nil)
    payload = serializer ? serializer.new(object, current_account: account).as_json : object
    # A client reacts by reading what the event announced, so it has to be committed by then.
    ActiveRecord.after_all_transactions_commit do
      redis.publish("timeline:#{account.id}", JSON.generate(event: event, payload: JSON.generate(payload)))
      MisskeyCompat::ChatStreaming.broadcast(redis, account, event, payload)
    end
  end

  def notify_members(conversation, message)
    conversation.memberships.includes(account: :user).where.not(account_id: message.account_id).find_each do |membership|
      next if membership.muted? || !membership.account.user&.settings&.[](:chat_notifications)

      broadcast_to(membership.account, 'chat.notification', message, REST::ChatMessageSerializer)
    end
  end
end
