# frozen_string_literal: true

class AddSortPriorityToBoardAnnouncements < ActiveRecord::Migration[8.0]
  def change
    add_column :board_announcements, :sort_priority, :integer, null: false, default: 0
  end
end
