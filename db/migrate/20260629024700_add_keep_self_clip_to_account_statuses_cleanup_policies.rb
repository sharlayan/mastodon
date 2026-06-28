# frozen_string_literal: true

class AddKeepSelfClipToAccountStatusesCleanupPolicies < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:account_statuses_cleanup_policies, :keep_self_clip)

    add_column :account_statuses_cleanup_policies, :keep_self_clip, :boolean, default: true, null: false
  end
end
