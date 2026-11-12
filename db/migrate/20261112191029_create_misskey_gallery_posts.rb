# frozen_string_literal: true

class CreateMisskeyGalleryPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_gallery_posts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.text :description
      t.bigint :media_attachment_ids, array: true, null: false, default: []
      t.boolean :sensitive, null: false, default: false
      t.integer :likes_count, null: false, default: 0
      t.timestamps
    end

    add_index :misskey_gallery_posts, :media_attachment_ids, using: :gin
    add_index :misskey_gallery_posts, :likes_count
  end
end
