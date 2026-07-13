# frozen_string_literal: true

class AddUniqueIndexToAntennaDomains < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute(<<~SQL.squish)
      DELETE FROM antenna_domains duplicate
      USING antenna_domains original
      WHERE duplicate.antenna_id = original.antenna_id
        AND duplicate.name = original.name
        AND duplicate.id > original.id
    SQL

    add_index :antenna_domains, [:antenna_id, :name], unique: true, algorithm: :concurrently
  end

  def down
    remove_index :antenna_domains, [:antenna_id, :name], algorithm: :concurrently
  end
end
