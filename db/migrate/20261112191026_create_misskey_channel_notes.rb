# frozen_string_literal: true

class CreateMisskeyChannelNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_channel_notes do |t|
      t.references :status, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :misskey_channel, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.timestamps
    end

    add_index :misskey_channel_notes, [:misskey_channel_id, :status_id], name: 'index_misskey_channel_notes_on_channel_and_status'
    add_index :misskey_channel_notes, [:misskey_channel_id, :account_id], name: 'index_misskey_channel_notes_on_channel_and_account'
  end
end
