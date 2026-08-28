# frozen_string_literal: true

class CreateAvatarDecorations < ActiveRecord::Migration[8.1]
  def change
    create_table :avatar_decorations do |t|
      t.string   :name, null: false, default: ''
      t.text     :description, default: ''

      t.string   :image_file_name
      t.string   :image_content_type
      t.integer  :image_file_size
      t.datetime :image_updated_at

      t.string :image_remote_url
      t.string :host
      t.string :remote_id

      t.boolean :approved, null: false, default: false

      t.timestamps null: false
    end

    add_index :avatar_decorations, :host
    add_index :avatar_decorations, %i(host remote_id), unique: true, where: 'host IS NOT NULL'
    add_index :avatar_decorations, :approved
  end
end
