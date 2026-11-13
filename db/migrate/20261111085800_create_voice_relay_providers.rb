# frozen_string_literal: true

class CreateVoiceRelayProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_relay_providers do |t|
      t.string :origin, null: false
      t.text :secret_ciphertext, null: false
      t.string :credential_version, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :validated, null: false, default: false
      t.datetime :last_checked_at
      t.string :last_error
      t.jsonb :capacity, null: false, default: {}
      t.timestamps
    end

    add_index :voice_relay_providers, :origin, unique: true
  end
end
