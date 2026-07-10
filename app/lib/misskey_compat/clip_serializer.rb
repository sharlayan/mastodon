# frozen_string_literal: true

class MisskeyCompat::ClipSerializer
  def self.serialize(clip, current_account: nil)
    new.serialize(clip, current_account: current_account)
  end

  def serialize(clip, current_account: nil)
    owner = current_account && clip.account_id == current_account.id

    {
      id: clip.id.to_s,
      createdAt: clip.created_at.iso8601,
      lastClippedAt: nil,
      userId: clip.account_id.to_s,
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
