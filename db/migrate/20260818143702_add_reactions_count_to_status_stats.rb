# frozen_string_literal: true

class AddReactionsCountToStatusStats < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:status_stats, :reactions_count)

    add_column :status_stats, :reactions_count, :bigint, null: false, default: 0
  end

  def down
    remove_column :status_stats, :reactions_count, if_exists: true
  end
end
