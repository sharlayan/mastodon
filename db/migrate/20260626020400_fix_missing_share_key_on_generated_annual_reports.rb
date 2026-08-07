# frozen_string_literal: true

class FixMissingShareKeyOnGeneratedAnnualReports < ActiveRecord::Migration[8.1]
  def up
    add_column :generated_annual_reports, :share_key, :string unless column_exists?(:generated_annual_reports, :share_key)

    add_column :collections, :item_count, :integer, default: 0, null: false unless column_exists?(:collections, :item_count)
  end

  def down; end
end
