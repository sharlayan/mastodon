# frozen_string_literal: true

class AddReactionToAccountStatusesCleanupPolicies < ActiveRecord::Migration[7.2]
  def change
    add_column :account_statuses_cleanup_policies, :keep_self_reaction, :boolean, null: false, default: true unless column_exists?(:account_statuses_cleanup_policies, :keep_self_reaction)
    add_column :account_statuses_cleanup_policies, :min_reactions, :integer, null: true unless column_exists?(:account_statuses_cleanup_policies, :min_reactions)
  end
end
