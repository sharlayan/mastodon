# frozen_string_literal: true

class CreateMisskeyRetentionAggregations < ActiveRecord::Migration[8.0]
  def change
    create_table :misskey_retention_aggregations do |t|
      t.string :date_key, null: false
      t.bigint :cohort_account_ids, array: true, null: false, default: []
      t.integer :users_count, null: false, default: 0
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    add_index :misskey_retention_aggregations, :date_key, unique: true
  end
end
