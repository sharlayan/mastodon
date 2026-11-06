# frozen_string_literal: true

class CreateFederationRequestFlushBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :federation_request_flush_batches do |t|
      t.string :batch_key, null: false
      t.datetime :created_at, null: false
    end

    add_index :federation_request_flush_batches, :batch_key, unique: true
    add_index :federation_request_flush_batches, :created_at
  end
end
