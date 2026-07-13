# frozen_string_literal: true

class AddMisskeyFieldsToBoardAnnouncements < ActiveRecord::Migration[8.0]
  def change
    add_column :board_announcements, :icon, :string, null: false, default: 'info'
    add_column :board_announcements, :display, :string, null: false, default: 'normal'
    add_column :board_announcements, :need_confirmation_to_read, :boolean, null: false, default: false
    add_column :board_announcements, :silence, :boolean, null: false, default: false
    add_column :board_announcements, :for_existing_users, :boolean, null: false, default: false
  end
end
