# frozen_string_literal: true

class AddFeaturesToInstanceMetadata < ActiveRecord::Migration[8.0]
  def change
    add_column :instance_metadata, :features, :jsonb, null: false, default: []
  end
end
