# frozen_string_literal: true

class MisskeyCompat::ChatSerializer
  include RoutingHelper

  class << self
    def message(message, viewer:)
      new(viewer).message(message)
    end

    def room(conversation, viewer:)
      new(viewer).room(conversation)
    end

    def invitation(invitation, viewer:)
      new(viewer).invitation(invitation)
    end

    def membership(membership, viewer:)
      new(viewer).membership(membership)
    end
  end

  def initialize(viewer)
    @viewer = viewer
  end

  def message(message)
    conversation = message.chat_conversation
    recipient = conversation.accounts.find { |account| account.id != message.account_id } if conversation.chat_direct?
    file = attachment(message)

    {
      id: mid(message.id),
      createdAt: message.created_at.iso8601(3),
      editedAt: message.edited_at&.iso8601(3),
      deletedAt: message.deleted_at&.iso8601(3),
      text: message.deleted? ? nil : message.text,
      fromUserId: mid(message.account_id),
      fromUser: user(message.account),
      toUserId: mid(recipient&.id),
      toUser: recipient && user(recipient),
      toRoomId: conversation.chat_group? ? mid(conversation.id) : nil,
      toRoom: conversation.chat_group? ? room(conversation) : nil,
      fileId: file&.fetch(:id),
      file: file,
      reactions: message.deleted? ? [] : reactions(message),
      emojis: message.deleted? ? {} : text_emojis(message),
    }
  end

  def room(conversation)
    membership = conversation.memberships.find { |item| item.account_id == @viewer.id }

    {
      id: mid(conversation.id),
      createdAt: conversation.created_at.iso8601(3),
      name: conversation.title,
      description: conversation.description.to_s,
      ownerId: mid(conversation.owner_account_id),
      owner: user(conversation.owner_account),
      isMuted: membership&.muted? || false,
      invitationExists: conversation.invitations.pending.exists?(invitee_account: @viewer),
      isArchived: conversation.archived?,
    }
  end

  def invitation(invitation)
    {
      id: mid(invitation.id),
      createdAt: invitation.created_at.iso8601(3),
      roomId: mid(invitation.chat_conversation_id),
      room: room(invitation.chat_conversation),
      userId: mid(invitation.invitee_account_id),
      user: user(invitation.invitee_account),
    }
  end

  def membership(membership)
    {
      id: mid(membership.id),
      createdAt: membership.created_at.iso8601(3),
      userId: mid(membership.account_id),
      user: user(membership.account),
      roomId: mid(membership.chat_conversation_id),
      room: room(membership.chat_conversation),
    }
  end

  private

  def mid(id)
    MisskeyCompat::MiId.encode(id)
  end

  def user(account)
    MisskeyCompat::UserSerializer.serialize(account, viewer: @viewer)
  end

  def attachment(message)
    return if message.deleted?

    media = message.media_attachments.first
    return if media.nil?

    # Drive metadata is reusable, but chat downloads must still check membership.
    token = MisskeyCompat::ChatMediaToken.generate(media, @viewer)
    MisskeyCompat::DriveFileSerializer.serialize(media).merge(
      url: media_proxy_url(media.id, :original, chat_token: token),
      thumbnailUrl: media_proxy_url(media.id, :small, chat_token: token)
    )
  end

  def reactions(message)
    message.reactions.includes(:account).map do |reaction|
      shortcode = ChatMessageReaction.shortcode_of(reaction.reaction)
      key = shortcode ? ":#{shortcode}@#{reaction.account.domain.presence || '.'}:" : reaction.reaction
      { user: user(reaction.account), reaction: key }
    end
  end

  def text_emojis(message)
    shortcodes = message.text.to_s.scan(/:([a-zA-Z0-9_+-]+):/).flatten.uniq
    CustomEmoji.where(shortcode: shortcodes, domain: message.account.domain, disabled: false).to_h do |emoji|
      [emoji.shortcode, full_asset_url(emoji.image.url)]
    end
  end
end
