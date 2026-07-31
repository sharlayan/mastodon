# frozen_string_literal: true

class AddReactionAcceptanceToStatuses < ActiveRecord::Migration[8.1]
  def change
    add_column :statuses, :reaction_acceptance, :string
  end
end
