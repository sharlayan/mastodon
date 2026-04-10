# frozen_string_literal: true

class AddRequiredRoleToAvatarDecorations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :avatar_decorations, :required_role, null: true, index: { algorithm: :concurrently }
  end
end
