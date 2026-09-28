# frozen_string_literal: true

class IsolateMisskeyRegistryAppTokens < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    safety_assured { add_column :misskey_access_grants, :native_user_token, :boolean, default: false, null: false }
    add_column :misskey_registry_items, :access_token_id, :bigint
    add_index :misskey_registry_items, [:account_id, :access_token_id, :scope], algorithm: :concurrently, name: 'index_misskey_registry_items_on_account_token_scope'
  end
end
