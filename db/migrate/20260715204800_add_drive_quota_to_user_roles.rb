# frozen_string_literal: true

class AddDriveQuotaToUserRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_roles, :drive_quota, :integer
  end
end
