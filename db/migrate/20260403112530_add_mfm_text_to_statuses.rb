# frozen_string_literal: true

class AddMfmTextToStatuses < ActiveRecord::Migration[7.2]
  def change
    add_column :statuses, :mfm_text, :text, null: true
  end
end
