# frozen_string_literal: true

class AddCategoryToAvatarDecorations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :avatar_decorations, :category, null: true, index: { algorithm: :concurrently }
  end
end
