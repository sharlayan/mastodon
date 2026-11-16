# frozen_string_literal: true

class CreateMisskeyAbuseReportRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_abuse_report_recipients do |t|
      t.string :name, null: false
      t.string :delivery_method, null: false
      t.boolean :active, null: false, default: true
      t.references :account, foreign_key: { on_delete: :cascade }
      t.references :webhook, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
  end
end
