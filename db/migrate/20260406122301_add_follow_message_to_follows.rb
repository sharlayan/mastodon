# frozen_string_literal: true

class AddFollowMessageToFollows < ActiveRecord::Migration[8.1]
  def change
    add_column :follows, :follow_message, :string, limit: 256
  end
end
