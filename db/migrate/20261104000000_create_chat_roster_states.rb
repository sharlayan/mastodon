# frozen_string_literal: true

class CreateChatRosterStates < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_roster_states do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :last_roster_at, null: false
      t.timestamps
    end

    add_index :chat_roster_states, [:chat_conversation_id, :account_id], unique: true, name: 'index_chat_roster_states_on_conversation_and_account'
  end
end
