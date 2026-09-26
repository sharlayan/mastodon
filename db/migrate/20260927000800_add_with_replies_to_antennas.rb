# frozen_string_literal: true

class AddWithRepliesToAntennas < ActiveRecord::Migration[8.1]
  def change
    add_column :antennas, :with_replies, :boolean, default: true, null: false
  end
end
