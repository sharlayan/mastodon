# frozen_string_literal: true

class CreateAvatarDecorationMutes < ActiveRecord::Migration[8.1]
  def change
    create_table :avatar_decoration_mutes do |t|
      t.references :account,        null: false, foreign_key: true
      t.references :target_account, null: true,  foreign_key: { to_table: :accounts }
      t.string     :target_domain,  null: true

      t.timestamps null: false
    end

    add_index :avatar_decoration_mutes, %i(account_id target_account_id),
              unique: true, where: 'target_account_id IS NOT NULL'
    add_index :avatar_decoration_mutes, %i(account_id target_domain),
              unique: true, where: 'target_domain IS NOT NULL'
  end
end
