# frozen_string_literal: true

class MisskeyCompat::DriveFolderSerializer
  def self.serialize(folder, detail: false)
    new.serialize(folder, detail: detail)
  end

  def serialize(folder, detail: false, visited_ids: Set.new)
    return unless visited_ids.add?(folder.id)

    result = {
      id: MisskeyCompat::MiId.encode(folder.id),
      createdAt: folder.created_at.iso8601,
      name: folder.name,
      parentId: MisskeyCompat::MiId.encode(folder.parent_id),
    }

    if detail
      result[:parent] = folder.parent && serialize(folder.parent, detail: true, visited_ids: visited_ids)
      result[:foldersCount] = folder.folders_count
      result[:filesCount] = folder.files_count
    end

    result
  end
end
