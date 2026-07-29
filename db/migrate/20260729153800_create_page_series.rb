# frozen_string_literal: true

class CreatePageSeries < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    create_table :page_series, id: :bigint, default: -> { "timestamp_id('page_series')" } do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :title, null: false
      t.text :description
      t.bigint :main_page_id
      t.timestamps
    end

    add_index :page_series, [:account_id, :title], unique: true
    add_index :page_series, :main_page_id, unique: true, where: 'main_page_id IS NOT NULL'
    add_foreign_key :page_series, :pages, column: :main_page_id, on_delete: :nullify, validate: false

    add_column :pages, :page_series_id, :bigint
    add_column :pages, :series_position, :integer, null: false, default: 0
    add_index :pages, :page_series_id, algorithm: :concurrently
    add_index :pages, [:page_series_id, :series_position, :id], name: 'index_pages_on_series_order', algorithm: :concurrently
    add_foreign_key :pages, :page_series, on_delete: :nullify, validate: false
  end

  def down
    remove_foreign_key :pages, :page_series
    remove_index :pages, name: 'index_pages_on_series_order'
    remove_index :pages, :page_series_id
    remove_column :pages, :series_position
    remove_column :pages, :page_series_id
    drop_table :page_series
  end
end
