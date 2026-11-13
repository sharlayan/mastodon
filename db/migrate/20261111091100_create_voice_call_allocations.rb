# frozen_string_literal: true

class CreateVoiceCallAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_call_allocations do |t|
      t.references :chat_conversation, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.references :voice_relay_provider, null: false, foreign_key: { on_delete: :cascade }
      t.string :room_key, null: false
      t.string :generation, null: false
      t.string :remote_id
      t.string :state, null: false, default: 'pending'
      t.integer :slots, null: false
      t.string :revision
      t.jsonb :participants, null: false, default: []
      t.boolean :unavailable, null: false, default: false
      t.datetime :renewed_at
      t.datetime :refreshed_at
      t.timestamps
    end

    add_index :voice_call_allocations, [:voice_relay_provider_id, :remote_id], unique: true, where: 'remote_id IS NOT NULL', name: 'index_voice_call_allocations_on_provider_and_remote_id'
    add_index :voice_call_allocations, :state, where: "state <> 'ended'", name: 'index_voice_call_allocations_unfinished'

    add_column :voice_relay_providers, :events_cursor, :string
  end
end
