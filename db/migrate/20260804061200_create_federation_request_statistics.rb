# frozen_string_literal: true

class CreateFederationRequestStatistics < ActiveRecord::Migration[8.1]
  def change
    create_table :federation_request_statistics do |t|
      t.string :domain, null: false
      t.datetime :bucket_at, null: false
      t.bigint :deliver_succeeded_count, null: false, default: 0
      t.bigint :deliver_failed_count, null: false, default: 0
      t.bigint :inbox_received_count, null: false, default: 0
      t.timestamps
    end

    add_index :federation_request_statistics, [:domain, :bucket_at], unique: true, name: 'index_federation_request_statistics_on_domain_and_bucket'
    add_index :federation_request_statistics, :bucket_at, name: 'index_federation_request_statistics_on_bucket_at'
  end
end
