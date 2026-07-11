# frozen_string_literal: true

class MisskeyCompat::ClipSerializer
  def self.serialize(clip, current_account: nil)
    new.serialize(clip, current_account: current_account)
  end

  def serialize(clip, current_account: nil)
    owner = current_account && clip.account_id == current_account.id

    {
      id: MisskeyCompat::MiId.encode(clip.id),
      createdAt: clip.created_at.iso8601,
      lastClippedAt: nil,
      userId: MisskeyCompat::MiId.encode(clip.account_id),
      user: MisskeyCompat::UserSerializer.serialize(clip.account),
      name: clip.title,
      description: clip.description,
      isPublic: clip.public?,
      favoritedCount: 0,
      isFavorited: false,
      notesCount: owner ? clip.clip_statuses.count : nil,
    }.compact
  end
end
