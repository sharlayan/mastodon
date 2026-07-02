# frozen_string_literal: true

class AddIndexOnBoardAnnouncementsSortPriority < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :board_announcements, :sort_priority, algorithm: :concurrently
  end
end
