# frozen_string_literal: true

class CreateAccountDomainMutes < ActiveRecord::Migration[8.1]
  def change
    create_table :account_domain_mutes do |t|
      t.bigint :account_id, null: false
      t.string :domain, null: false
      t.boolean :hide_from_home, default: false, null: false

      t.timestamps
    end

    add_index :account_domain_mutes, [:account_id, :domain], unique: true
  end
end
