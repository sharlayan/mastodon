# frozen_string_literal: true

class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string     :title,                  null: false, default: ''
      t.string     :name,                   null: false
      t.text       :summary,                null: true
      t.jsonb      :content,                null: false, default: []
      t.boolean    :align_center,           null: false, default: false
      t.boolean    :hide_title_when_pinned, null: false, default: false
      t.string     :font,                   null: false, default: 'sans-serif'
      t.references :eye_catching_media_attachment, null: true, foreign_key: { to_table: :media_attachments, on_delete: :nullify }
      t.integer    :likes_count, null: false, default: 0

      t.timestamps null: false
    end

    add_index :pages, [:account_id, :name], unique: true
    add_index :pages, :likes_count
  end
end
