# frozen_string_literal: true

class AddLimitedScopeToStatuses < ActiveRecord::Migration[8.1]
  def change
    add_column :statuses, :limited_scope, :integer
  end
end
