# frozen_string_literal: true

class CreateStatusDrafts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :status_drafts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    add_reference :media_attachments, :status_draft, index: false
    add_index :media_attachments, :status_draft_id, algorithm: :concurrently
    add_foreign_key :media_attachments, :status_drafts, on_delete: :nullify, validate: false
  end
end
