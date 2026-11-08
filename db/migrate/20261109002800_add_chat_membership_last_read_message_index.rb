# frozen_string_literal: true

class AddChatMembershipLastReadMessageIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :chat_memberships, :last_read_message_id, where: 'last_read_message_id IS NOT NULL', algorithm: :concurrently, if_not_exists: true
  end
end
