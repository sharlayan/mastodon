# frozen_string_literal: true

class AddPublicTimelineStreamSuppressionToRelays < ActiveRecord::Migration[8.1]
  def change
    add_column :relays, :suppress_public_timeline_stream, :boolean, default: false, null: false
  end
end
