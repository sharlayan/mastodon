# frozen_string_literal: true

class AddReferencedMediaAttachmentIdsToPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :pages, :referenced_media_attachment_ids, :bigint, array: true, default: [], null: false

    safety_assured { execute <<~SQL.squish }
      UPDATE pages
      SET referenced_media_attachment_ids = COALESCE((
        SELECT array_agg(DISTINCT (file_id #>> '{}')::bigint)
        FROM jsonb_path_query(pages.content, '$.**.fileId') AS file_id
        WHERE jsonb_typeof(file_id) = 'string'
          AND (file_id #>> '{}') ~ '^[0-9]{1,18}$'
      ), '{}')
    SQL

    add_index :pages, :referenced_media_attachment_ids, using: :gin, algorithm: :concurrently
  end

  def down
    remove_index :pages, :referenced_media_attachment_ids, algorithm: :concurrently
    remove_column :pages, :referenced_media_attachment_ids
  end
end
