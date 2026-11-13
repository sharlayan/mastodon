# frozen_string_literal: true

class CreateMisskeyUserPageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_user_page_views do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :bucket_at, null: false
      t.boolean :visitor, null: false, default: false
      t.string :viewer_key, null: false
      t.integer :views, null: false, default: 0
      t.timestamps
    end

    add_index :misskey_user_page_views, [:account_id, :bucket_at, :visitor, :viewer_key], unique: true, name: 'index_misskey_user_page_views_on_viewer_bucket'
  end
end
