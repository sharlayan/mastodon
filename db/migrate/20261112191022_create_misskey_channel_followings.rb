# frozen_string_literal: true

class CreateMisskeyChannelFollowings < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_channel_followings do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :misskey_channel, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :misskey_channel_followings, [:account_id, :misskey_channel_id], unique: true, name: 'index_misskey_channel_followings_on_account_and_channel'
  end
end
