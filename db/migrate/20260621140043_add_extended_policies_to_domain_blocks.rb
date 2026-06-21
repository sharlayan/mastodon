# frozen_string_literal: true

class AddExtendedPoliciesToDomainBlocks < ActiveRecord::Migration[8.0]
  def change
    add_column :domain_blocks, :reject_favourite, :boolean, default: false, null: false
    add_column :domain_blocks, :reject_relay, :boolean, default: false, null: false
    add_column :domain_blocks, :block_trends, :boolean, default: false, null: false
    add_column :domain_blocks, :hidden, :boolean, default: false, null: false
  end
end
