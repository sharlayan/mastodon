# frozen_string_literal: true

class MisskeyCompat::WebhookTestContent
  DUMMY_TIME = Time.utc(2000, 1, 1)

  def self.for(type)
    new.for(type)
  end

  def for(type)
    case type
    when 'note' then { note: note }
    when 'reply' then { note: note(id: 'dummy-reply-1', replyId: 'dummy-note-1', reply: note) }
    when 'renote' then { note: note(id: 'dummy-renote-1', user_index: 2, text: nil, renoteId: 'dummy-note-1', renote: note) }
    when 'mention' then { note: note(id: 'dummy-mention-1', text: '@dummy2 This is a mention to you', mentions: ['dummy-user-2']) }
    when 'follow' then { user: user(1, detailed: true) }
    when 'followed' then { user: user(2) }
    when 'unfollow' then { user: user(3, detailed: true) }
    end
  end

  private

  def note(id: 'dummy-note-1', user_index: 1, text: 'This is a dummy note for testing purposes', **overrides)
    {
      id: id,
      createdAt: DUMMY_TIME.iso8601(3),
      userId: "dummy-user-#{user_index}",
      user: user(user_index),
      text: text,
      cw: nil,
      visibility: 'public',
      localOnly: false,
      reactionAcceptance: nil,
      renoteCount: 0,
      repliesCount: 0,
      reactionCount: 0,
      reactions: {},
      reactionEmojis: {},
      emojis: {},
      fileIds: [],
      files: [],
      replyId: nil,
      renoteId: nil,
    }.merge(overrides)
  end

  def user(index, detailed: false)
    data = {
      id: "dummy-user-#{index}",
      name: "DummyUser#{index}",
      username: "dummy#{index}",
      host: nil,
      avatarUrl: nil,
      avatarBlurhash: nil,
      avatarDecorations: [],
      isBot: false,
      isCat: false,
      emojis: {},
      onlineStatus: 'unknown',
      badgeRoles: [],
    }
    return data unless detailed

    data.merge(
      createdAt: DUMMY_TIME.iso8601(3),
      description: nil,
      followersCount: 10,
      followingCount: 5,
      notesCount: 30,
      isFollowing: false,
      isFollowed: false,
      hasPendingFollowRequestFromYou: false,
      hasPendingFollowRequestToYou: false,
      isBlocking: false,
      isBlocked: false,
      isMuted: false,
      isRenoteMuted: false
    )
  end
end
