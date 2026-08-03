# frozen_string_literal: true

class AddPageWritingStatistics < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :pages, :text_characters_count, :integer
    add_column :page_series, :displayed, :boolean, default: true, null: false

    create_table :page_daily_statistics do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :activity_date, null: false
      t.integer :characters_delta, null: false, default: 0
      t.integer :pages_created_count, null: false, default: 0
      t.integer :pages_updated_count, null: false, default: 0
      t.timestamps
    end

    add_index :page_daily_statistics, [:account_id, :activity_date], unique: true, name: 'index_page_daily_statistics_on_account_and_date'
  end

  def down
    drop_table :page_daily_statistics
    remove_column :page_series, :displayed
    remove_column :pages, :text_characters_count
  end
end
