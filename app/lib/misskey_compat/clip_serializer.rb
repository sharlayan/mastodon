# frozen_string_literal: true

class MisskeyCompat::ClipSerializer
  def self.serialize(clip, current_account: nil, relationships: nil)
    new.serialize(clip, current_account: current_account, relationships: relationships)
  end

  def serialize(clip, current_account: nil, relationships: nil)
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
      favoritedCount: relationships ? relationships.favourites_count_map.fetch(clip.id, 0) : clip.clip_favourites.count,
      isFavorited: favourited_value(clip, current_account, relationships),
      notesCount: owner ? notes_count(clip, relationships) : nil,
    }.compact
  end

  private

  def favourited_value(clip, current_account, relationships)
    return if current_account.nil?
    return relationships.favourited_map.fetch(clip.id, false) if relationships

    clip.favourited_by?(current_account)
  end

  def notes_count(clip, relationships)
    return relationships.statuses_count_map.fetch(clip.id, 0) if relationships

    clip.clip_statuses.count
  end
end
