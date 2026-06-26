# frozen_string_literal: true

class AddExtraPermissionsToUserRoles < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:user_roles, :extra_permissions)

    add_column :user_roles, :extra_permissions, :bigint, default: 0, null: false
  end
end
