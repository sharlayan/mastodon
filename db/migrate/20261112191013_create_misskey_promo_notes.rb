# frozen_string_literal: true

class CreateMisskeyPromoNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_promo_notes do |t|
      t.references :status, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :expires_at, null: false
      t.timestamps
    end
  end
end
