# frozen_string_literal: true

class RemoveChatInvitationsUri < ActiveRecord::Migration[8.1]
  def change
    remove_column :chat_invitations, :uri, :string, if_exists: true
  end
end
