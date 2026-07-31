# frozen_string_literal: true

class AddNonLocalOnlyIndexToStatuses < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :statuses,
              :id,
              name: 'index_statuses_not_local_only',
              where: '(local_only IS NOT TRUE)',
              order: { id: :desc },
              algorithm: :concurrently
  end
end
