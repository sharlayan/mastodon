# frozen_string_literal: true

class RemoveChatInvitationsUri < ActiveRecord::Migration[8.1]
  def up
    safety_assured { remove_column :chat_invitations, :uri, if_exists: true }
  end

  def down; end
end
