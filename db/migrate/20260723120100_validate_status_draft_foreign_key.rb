# frozen_string_literal: true

class ValidateStatusDraftForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :media_attachments, :status_drafts
  end
end
