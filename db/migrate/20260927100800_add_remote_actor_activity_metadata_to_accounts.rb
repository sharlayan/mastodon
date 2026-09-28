# frozen_string_literal: true

class AddRemoteActorActivityMetadataToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :remote_actor_published_at, :datetime
    add_column :accounts, :remote_outbox_total_items, :bigint
  end
end
