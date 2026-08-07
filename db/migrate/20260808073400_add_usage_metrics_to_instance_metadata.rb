# frozen_string_literal: true

class AddUsageMetricsToInstanceMetadata < ActiveRecord::Migration[8.0]
  def change
    add_column :instance_metadata, :local_users_count, :bigint
    add_column :instance_metadata, :local_posts_count, :bigint
    add_column :instance_metadata, :local_comments_count, :bigint
    add_column :instance_metadata, :active_users_monthly_count, :bigint
    add_column :instance_metadata, :active_users_halfyear_count, :bigint
    add_column :instance_metadata, :known_instances_count, :bigint
    add_column :instance_metadata, :open_registrations, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn -- nil means that the remote server did not publish this field
    add_column :instance_metadata, :usage_updated_at, :datetime
  end
end
