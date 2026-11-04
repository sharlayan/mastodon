# frozen_string_literal: true

class AddMemberTimeToChatRosterStates < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_roster_states, :last_member_at, :datetime
    add_column :chat_invitations, :invite_published_at, :datetime
  end
end
