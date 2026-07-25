# frozen_string_literal: true

class CreateMisskeyFederationInstanceStats < ActiveRecord::Migration[8.0]
  def change
    create_table :misskey_federation_instance_stats do |t|
      t.string :domain, null: false
      t.datetime :first_retrieved_at
      t.integer :users_count, null: false, default: 0
      t.integer :notes_count, null: false, default: 0
      t.integer :following_count, null: false, default: 0
      t.integer :followers_count, null: false, default: 0
      t.timestamps
    end

    add_index :misskey_federation_instance_stats, :domain, unique: true
  end
end
