# frozen_string_literal: true

class CreateVoiceCallRemoteSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_call_remote_sessions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }, index: { name: 'index_voice_call_remote_sessions_on_conversation' }
      t.string :identity, null: false
      t.string :room_name, null: false
      t.string :origin, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :voice_call_remote_sessions, [:identity, :room_name], unique: true, name: 'index_voice_call_remote_sessions_on_identity_and_room'
    add_index :voice_call_remote_sessions, :account_id, name: 'index_voice_call_remote_sessions_on_account_id'
  end
end
