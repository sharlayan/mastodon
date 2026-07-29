# frozen_string_literal: true

class AddCoverMediaAttachmentToPageSeries < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :page_series, :cover_media_attachment, type: :bigint, index: { algorithm: :concurrently }
    add_foreign_key :page_series, :media_attachments, column: :cover_media_attachment_id, on_delete: :nullify, validate: false
  end
end
