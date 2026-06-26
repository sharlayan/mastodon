# frozen_string_literal: true

class CreateClipStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :clip_statuses do |t|
      t.references :clip,   null: false, foreign_key: { on_delete: :cascade }
      t.references :status, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps null: false
    end

    add_index :clip_statuses, %i(clip_id status_id), unique: true
  end
end
