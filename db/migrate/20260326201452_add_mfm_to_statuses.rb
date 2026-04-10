# frozen_string_literal: true

class AddMfmToStatuses < ActiveRecord::Migration[7.2]
  def change
    add_column :statuses, :mfm, :boolean, default: false, null: false
  end
end
