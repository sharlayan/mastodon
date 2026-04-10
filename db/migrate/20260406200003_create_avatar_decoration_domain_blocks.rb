# frozen_string_literal: true

class CreateAvatarDecorationDomainBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :avatar_decoration_domain_blocks do |t|
      t.string :domain, null: false

      t.timestamps null: false
    end

    add_index :avatar_decoration_domain_blocks, :domain, unique: true
  end
end
