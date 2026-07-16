# frozen_string_literal: true

class CreatePageReports < ActiveRecord::Migration[8.0]
  def change
    create_table :page_reports do |t|
      t.references :page, null: false, foreign_key: { on_delete: :cascade }
      t.references :report, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :page_reports, [:page_id, :report_id], unique: true
  end
end
