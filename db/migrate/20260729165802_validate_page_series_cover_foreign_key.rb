# frozen_string_literal: true

class ValidatePageSeriesCoverForeignKey < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :page_series, :media_attachments, column: :cover_media_attachment_id
  end
end
