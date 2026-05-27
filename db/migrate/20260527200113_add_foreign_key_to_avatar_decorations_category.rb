# frozen_string_literal: true

class AddForeignKeyToAvatarDecorationsCategory < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :avatar_decorations, :avatar_decoration_categories, column: :category_id, on_delete: :nullify, validate: false
  end
end
