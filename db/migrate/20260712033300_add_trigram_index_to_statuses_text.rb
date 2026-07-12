# frozen_string_literal: true

class AddTrigramIndexToStatusesText < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')

    safety_assured do
      add_index :statuses, :text, using: :gin, opclass: :gin_trgm_ops, name: 'index_statuses_on_text_trgm', algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    remove_index :statuses, name: 'index_statuses_on_text_trgm', if_exists: true
  end
end
