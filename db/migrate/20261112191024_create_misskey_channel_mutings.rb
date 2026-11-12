# frozen_string_literal: true

class CreateMisskeyChannelMutings < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_channel_mutings do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :misskey_channel, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :expires_at
      t.timestamps
    end

    add_index :misskey_channel_mutings, [:account_id, :misskey_channel_id], unique: true, name: 'index_misskey_channel_mutings_on_account_and_channel'
  end
end
