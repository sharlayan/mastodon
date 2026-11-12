# frozen_string_literal: true

class CreateMisskeyGalleryLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_gallery_likes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :misskey_gallery_post, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :misskey_gallery_likes, [:account_id, :misskey_gallery_post_id], unique: true, name: 'index_misskey_gallery_likes_on_account_id_and_post_id'
  end
end
