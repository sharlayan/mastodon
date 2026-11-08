# frozen_string_literal: true

class CreateChatDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_conversations do |t|
      t.integer :conversation_type, null: false, default: 0
      t.string :direct_key
      t.string :title
      t.text :description
      t.references :owner_account, foreign_key: { to_table: :accounts, on_delete: :nullify }, index: true
      t.bigint :last_message_id
      t.timestamps
    end

    add_index :chat_conversations, :direct_key, unique: true, where: 'direct_key IS NOT NULL'
    add_index :chat_conversations, :last_message_id

    create_table :chat_memberships do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.integer :role, null: false, default: 0
      t.bigint :last_read_message_id
      t.boolean :muted, null: false, default: false
      t.timestamps
    end

    add_index :chat_memberships, [:chat_conversation_id, :account_id], unique: true, name: :index_chat_memberships_on_conversation_and_account
    add_index :chat_memberships, [:account_id, :chat_conversation_id], name: :index_chat_memberships_on_account_and_conversation

    create_table :chat_messages do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :reply_to, foreign_key: { to_table: :chat_messages, on_delete: :nullify }
      t.text :text
      t.string :uri
      t.datetime :edited_at
      t.datetime :deleted_at
      t.datetime :hidden_at
      t.timestamps
    end

    add_index :chat_messages, :uri, unique: true, where: 'uri IS NOT NULL'
    create_table :chat_message_reactions do |t|
      t.references :chat_message, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :reaction, null: false
      t.timestamps
    end

    add_index :chat_message_reactions, [:chat_message_id, :account_id, :reaction], unique: true, name: :index_chat_message_reactions_on_message_account_reaction

    create_table :chat_invitations do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :inviter_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.references :invitee_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.integer :state, null: false, default: 0
      t.boolean :ignored, null: false, default: false
      t.timestamps
    end

    add_index :chat_invitations, [:chat_conversation_id, :invitee_account_id], unique: true, where: 'state = 0', name: :index_pending_chat_invitations
  end
end
