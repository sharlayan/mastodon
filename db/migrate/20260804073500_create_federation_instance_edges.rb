# frozen_string_literal: true

class CreateFederationInstanceEdges < ActiveRecord::Migration[8.1]
  def change
    create_table :federation_instance_edges do |t|
      t.string :source_domain
      t.string :target_domain
      t.bigint :reblogs_count, null: false, default: 0
      t.bigint :replies_count, null: false, default: 0
      t.bigint :quotes_count, null: false, default: 0
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :federation_instance_edges, [:source_domain, :target_domain], unique: true, nulls_not_distinct: true, name: 'index_federation_instance_edges_on_source_and_target'
    add_index :federation_instance_edges, :target_domain, name: 'index_federation_instance_edges_on_target_domain'
    add_index :federation_instance_edges, :updated_at, name: 'index_federation_instance_edges_on_updated_at'
  end
end
