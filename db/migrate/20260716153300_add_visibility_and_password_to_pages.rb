# frozen_string_literal: true

class AddVisibilityAndPasswordToPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :pages, :visibility, :string, default: 'public', null: false unless column_exists?(:pages, :visibility)
    add_column :pages, :access_password_digest, :string unless column_exists?(:pages, :access_password_digest)
    add_index :pages, :visibility, algorithm: :concurrently unless index_exists?(:pages, :visibility)

    safety_assured do
      execute <<~SQL.squish
        UPDATE pages
        SET visibility = 'private'
        WHERE draft = TRUE
      SQL
    end
  end

  def down
    remove_index :pages, :visibility
    remove_column :pages, :access_password_digest
    remove_column :pages, :visibility
  end
end
