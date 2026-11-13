# frozen_string_literal: true

class CreateVoiceCallRemoteStates < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_call_remote_states do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true, name: 'index_voice_call_remote_states_on_conversation' }
      t.jsonb :participants, null: false, default: []
      t.bigint :remote_updated_at, null: false
      t.timestamps
    end
  end
end
