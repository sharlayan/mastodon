# frozen_string_literal: true

class CreateMisskeyChannelFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_channel_favorites do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :misskey_channel, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :misskey_channel_favorites, [:account_id, :misskey_channel_id], unique: true, name: 'index_misskey_channel_favorites_on_account_and_channel'
  end
end
