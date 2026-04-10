# frozen_string_literal: true

class AddSupportsAvatarDecorationsToInstanceMetadata < ActiveRecord::Migration[7.2]
  def change
    add_column :instance_metadata, :supports_avatar_decorations, :boolean, default: false, null: false
  end
end
