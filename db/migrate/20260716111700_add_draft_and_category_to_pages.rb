# frozen_string_literal: true

class AddDraftAndCategoryToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :draft, :boolean, null: false, default: false
    add_column :pages, :category, :string
  end
end
