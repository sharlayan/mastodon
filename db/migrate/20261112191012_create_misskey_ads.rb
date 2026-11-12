# frozen_string_literal: true

class CreateMisskeyAds < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_ads do |t|
      t.datetime :expires_at, null: false
      t.datetime :starts_at, null: false
      t.string :place, null: false, default: ''
      t.string :priority, null: false, default: ''
      t.integer :ratio, null: false, default: 1
      t.string :url, null: false
      t.string :image_url, null: false
      t.text :memo, null: false, default: ''
      t.integer :day_of_week, null: false, default: 0
      t.boolean :is_sensitive, null: false, default: false
      t.timestamps
    end

    add_index :misskey_ads, [:starts_at, :expires_at]
  end
end
