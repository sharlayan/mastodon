# frozen_string_literal: true

class AddReactionAcceptanceToStatuses < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:statuses, :reaction_acceptance)

    add_column :statuses, :reaction_acceptance, :string
  end

  def down
    remove_column :statuses, :reaction_acceptance, if_exists: true
  end
end
