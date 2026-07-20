# frozen_string_literal: true

class AddIsMainToPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :pages, :is_main, :boolean, default: false, null: false unless column_exists?(:pages, :is_main)
    add_index :pages, :account_id, unique: true, where: 'is_main', name: 'index_pages_on_account_id_where_is_main', algorithm: :concurrently unless index_exists?(:pages, :account_id, name: 'index_pages_on_account_id_where_is_main')
  end

  def down
    remove_index :pages, name: 'index_pages_on_account_id_where_is_main', algorithm: :concurrently if index_exists?(:pages, :account_id, name: 'index_pages_on_account_id_where_is_main')
    remove_column :pages, :is_main if column_exists?(:pages, :is_main)
  end
end
