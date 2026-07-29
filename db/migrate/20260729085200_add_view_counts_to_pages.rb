# frozen_string_literal: true

class AddViewCountsToPages < ActiveRecord::Migration[8.0]
  def change
    add_column :pages, :authenticated_views_count, :integer, null: false, default: 0
    add_column :pages, :anonymous_views_count, :integer, null: false, default: 0
  end
end
