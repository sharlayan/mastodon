# frozen_string_literal: true

class CreateCircleStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :circle_statuses do |t|
      t.references :circle, null: false, foreign_key: { on_delete: :cascade }
      t.references :status, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps null: false
    end

    add_index :circle_statuses, %i(circle_id status_id), unique: true
  end
end
