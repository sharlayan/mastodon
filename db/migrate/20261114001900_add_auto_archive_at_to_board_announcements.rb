# frozen_string_literal: true

class AddAutoArchiveAtToBoardAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :board_announcements, :auto_archive_at, :datetime
  end
end
