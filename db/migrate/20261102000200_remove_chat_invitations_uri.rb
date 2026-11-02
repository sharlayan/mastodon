# frozen_string_literal: true

class RemoveChatInvitationsUri < ActiveRecord::Migration[8.1]
  # Only databases that ran an earlier draft of this branch have the column, and no
  # released code reads it, so there is nothing to ignore before removing it.
  def up
    safety_assured { remove_column :chat_invitations, :uri, if_exists: true }
  end

  def down; end
end
