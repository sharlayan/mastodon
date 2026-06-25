# frozen_string_literal: true

class MakeBoardAnnouncementAttachmentsAnnouncementOptional < ActiveRecord::Migration[8.0]
  def up
    change_column_null :board_announcement_attachments, :board_announcement_id, true
  end

  def down
    change_column_null :board_announcement_attachments, :board_announcement_id, false
  end
end
