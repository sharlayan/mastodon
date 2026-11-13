# frozen_string_literal: true

class AddDiceToChatMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_messages, :dice, :jsonb
  end
end
