# frozen_string_literal: true

class AddInstancesThemeColorForMisskeyStyleServerBar < ActiveRecord::Migration[8.0]
  def change
    create_table :instance_metadata do |t|
      t.string :domain, null: false, index: { unique: true }
      t.string :software
      t.string :version
      t.string :theme_color
      t.datetime :theme_color_updated_at
      t.string :favicon_url
      t.datetime :metadata_updated_at

      t.timestamps
    end

    add_index :instance_metadata, :theme_color_updated_at
  end
end
