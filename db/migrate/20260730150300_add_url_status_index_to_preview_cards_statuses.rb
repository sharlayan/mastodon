# frozen_string_literal: true

class AddURLStatusIndexToPreviewCardsStatuses < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :preview_cards_statuses, [:url, :status_id], algorithm: :concurrently
  end
end
