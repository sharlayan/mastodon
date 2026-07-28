# frozen_string_literal: true

class AddPageLimitToUserRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_roles, :page_limit, :integer, null: false, default: 500
  end
end
