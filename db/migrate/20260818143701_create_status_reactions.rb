# frozen_string_literal: true

class CreateStatusReactions < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:status_reactions)

    create_table :status_reactions, id: :bigint, default: -> { "timestamp_id('status_reactions'::text)" } do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :status, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, default: ''
      t.references :custom_emoji, null: true, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :status_reactions, [:account_id, :status_id, :name], unique: true, name: :index_status_reactions_on_account_id_and_status_id

    Mastodon::Snowflake.ensure_id_sequences_exist
  end

  def down
    drop_table :status_reactions, if_exists: true
  end
end
