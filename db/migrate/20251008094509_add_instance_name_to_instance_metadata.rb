# frozen_string_literal: true

class AddInstanceNameToInstanceMetadata < ActiveRecord::Migration[8.0]
  def change
    add_column :instance_metadata, :instance_name, :string
  end
end
