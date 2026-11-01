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
    raise Error, 'All chat participants must be local accounts' unless participants.all?(&:local?)

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
      attachments.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }
      conversation.update!(last_message: message)
      membership.update!(last_read_message: message)
    end
    broadcast(conversation, 'chat.message', message, REST::ChatMessageSerializer)
    notify_members(conversation, message)
    message
  end

  def update_message(account, message, text:)
    raise Forbidden unless message.account_id == account.id

    ensure_conversation_writable!(message.chat_conversation)
    ensure_direct_participants_not_blocked!(account, message.chat_conversation)
    raise Error, 'Deleted messages cannot be edited' if message.deleted?

    message.update!(text: text.to_s.strip.presence, edited_at: Time.current)
    broadcast(message.chat_conversation, 'chat.message_update', message, REST::ChatMessageSerializer)
    message
  end

  def delete_message(account, message)
    raise Forbidden unless message.account_id == account.id

    return hide_message(account, message) if hide_instead_of_delete?(message)

    message.transaction do
      message.reactions.destroy_all
      message.chat_message_media_attachments.destroy_all
      message.update!(text: nil, deleted_at: Time.current)
    end
    broadcast(message.chat_conversation, 'chat.message_delete', { id: message.id.to_s, conversation_id: message.chat_conversation_id.to_s })
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
    record
  end

  def unreact(account, message, reaction)
    membership!(account, message.chat_conversation)
    ensure_conversation_writable!(message.chat_conversation)
    record = message.reactions.find_by!(account: account, reaction: reaction)
    record.destroy!
    broadcast(message.chat_conversation, 'chat.reaction_delete', { message_id: message.id.to_s, account_id: account.id.to_s, reaction: reaction })
  end

  def invite(account, conversation, invitee)
    membership = membership!(account, conversation)
    raise Forbidden unless conversation.chat_group? && membership.owner?

    ensure_conversation_writable!(conversation)
    raise Error, 'Remote accounts are not supported yet' unless invitee.local?
    raise Error, 'Account is already a member' if conversation.memberships.exists?(account: invitee)
    raise Forbidden if blocked_in_either_direction?(account, invitee)
    raise Forbidden unless invitee.user&.settings&.[](:chat_allow_group_invites)

    invitation = conversation.with_lock do
      existing_invitation = conversation.invitations.pending.find_by(invitee_account: invitee)
      next existing_invitation if existing_invitation

      ensure_group_capacity!(conversation, include_pending: true)
      conversation.invitations.create!(inviter_account: account, invitee_account: invitee)
    end
    broadcast_to(invitee, 'chat.invitation', invitation, REST::ChatInvitationSerializer)
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
    broadcast(conversation, 'chat.conversation_update', conversation, REST::ChatConversationSerializer)
    conversation
  end

  def reject_invitation(account, invitation)
    raise Forbidden unless invitation.invitee_account_id == account.id && invitation.pending?

    invitation.update!(state: :rejected)
  end

  def cancel_invitation(account, invitation)
    raise Forbidden unless invitation.inviter_account_id == account.id && invitation.pending?

    invitation.update!(state: :cancelled)
  end

  def leave(account, conversation)
    membership = membership!(account, conversation)
    raise Error, 'The owner cannot leave the room' if membership.owner?

    membership.destroy!
    broadcast(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: account.id.to_s })
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
    conversation
  end

  private

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
    raise Forbidden unless invitees.all? { |participant| participant.user&.settings&.[](:chat_allow_group_invites) }

    ChatConversation.transaction do
      conversation = ChatConversation.create!(conversation_type: :group, owner_account: account, title: title, description: description)
      conversation.memberships.create!(account: account, role: :owner)
      invitees.each do |participant|
        conversation.invitations.create!(inviter_account: account, invitee_account: participant)
      end
      conversation
    end
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
    first_account.blocking?(second_account) || second_account.blocking?(first_account)
  end

  def media_attachments(account, ids)
    normalized_ids = ids.map(&:to_s).uniq
    raise Error, "A chat message can contain up to #{Setting.chat_max_attachments} attachments" if normalized_ids.size > Setting.chat_max_attachments

    attachments = MediaAttachment.where(id: normalized_ids, account: account, status_id: nil).to_a
    raise Error, 'One or more media attachments were not found' unless attachments.size == normalized_ids.size
    raise Error, 'One or more media attachments are already in use' if ChatMessageMediaAttachment.exists?(media_attachment_id: normalized_ids)

    attachments
  end

  def direct_chat_allowed?(sender, recipient)
    return false unless recipient.local?

    policy = recipient.user&.settings&.[](:chat_policy) || 'nobody'
    case policy
    when 'everyone' then true
    when 'followers' then recipient.followed_by?(sender)
    when 'following' then recipient.following?(sender)
    when 'mutuals' then recipient.following?(sender) && recipient.followed_by?(sender)
    else false
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
