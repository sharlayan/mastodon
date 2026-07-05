# frozen_string_literal: true

class CreateAntennas < ActiveRecord::Migration[8.1]
  def change
    create_table :antennas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :title, null: false, default: ''

      t.jsonb :keywords, null: false, default: []
      t.jsonb :exclude_keywords, null: false, default: []
      t.jsonb :exclude_accounts, null: false, default: []
      t.jsonb :exclude_domains, null: false, default: []
      t.jsonb :exclude_tags, null: false, default: []

      t.boolean :any_keywords, null: false, default: true
      t.boolean :any_accounts, null: false, default: true
      t.boolean :any_domains, null: false, default: true
      t.boolean :any_tags, null: false, default: true

      t.boolean :available, null: false, default: true
      t.boolean :with_media_only, null: false, default: false
      t.boolean :ignore_reblog, null: false, default: false

      t.timestamps
    end
  end
end
