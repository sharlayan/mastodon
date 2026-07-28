# frozen_string_literal: true

class AddDailyPageLimitToUserRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_roles, :daily_page_limit, :integer, null: false, default: 20
  end
end
