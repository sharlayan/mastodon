# frozen_string_literal: true

class CreateMisskeyAchievements < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_achievements do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.datetime :unlocked_at, null: false
      t.timestamps
    end

    add_index :misskey_achievements, [:account_id, :name], unique: true
  end
end
