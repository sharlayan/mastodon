# frozen_string_literal: true

class CreateBoardAnnouncements < ActiveRecord::Migration[8.0]
  def change
    create_table :board_announcements do |t|
      t.string :title, null: false, default: ''
      t.text :text, null: false, default: ''
      t.text :text_html, null: false, default: ''
      t.boolean :published, null: false, default: false
      t.datetime :published_at

      t.timestamps
    end

    add_index :board_announcements, :published_at
  end
end
