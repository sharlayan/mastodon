# frozen_string_literal: true

class CreateReactionMutes < ActiveRecord::Migration[8.1]
  def change
    create_table :reaction_mutes do |t|
      t.references :account,        null: false, foreign_key: { on_delete: :cascade }
      t.references :target_account, null: true,  foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.string     :target_domain,  null: true

      t.timestamps null: false
    end

    add_index :reaction_mutes, %i(account_id target_account_id),
              unique: true, where: 'target_account_id IS NOT NULL'
    add_index :reaction_mutes, %i(account_id target_domain),
              unique: true, where: 'target_domain IS NOT NULL'
  end
end
