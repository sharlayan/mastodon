# frozen_string_literal: true

class CreateAvatarDecorationCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :avatar_decoration_categories do |t|
      t.string :name
      t.timestamps
    end

    add_index :avatar_decoration_categories, :name, unique: true
  end
end
