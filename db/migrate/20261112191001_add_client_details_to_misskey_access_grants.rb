# frozen_string_literal: true

class AddClientDetailsToMisskeyAccessGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :misskey_access_grants, :name, :string
    add_column :misskey_access_grants, :description, :text
    add_column :misskey_access_grants, :icon_url, :string
  end
end
