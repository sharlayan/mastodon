# frozen_string_literal: true

class CreateMisskeyAbuseReportResolutions < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_abuse_report_resolutions do |t|
      t.references :report, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :resolved_as, null: false
      t.timestamps
    end
  end
end
