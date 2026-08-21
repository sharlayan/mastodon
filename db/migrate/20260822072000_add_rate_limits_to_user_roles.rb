# frozen_string_literal: true

class AddRateLimitsToUserRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_roles, :api_rate_limit, :integer
    add_column :user_roles, :api_token_rate_limit, :integer
    add_column :user_roles, :api_paging_rate_limit, :integer
    add_column :user_roles, :api_media_rate_limit, :integer
    add_column :user_roles, :api_delete_rate_limit, :integer
    add_column :user_roles, :drive_upload_rate_limit, :integer
  end
end
