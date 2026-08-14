# frozen_string_literal: true

class UseSnowflakeIdsForNewConversations < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute("ALTER TABLE conversations ALTER COLUMN id SET DEFAULT timestamp_id('conversations')")
    end

    Mastodon::Snowflake.ensure_id_sequences_exist
  end

  def down
    safety_assured do
      execute("ALTER TABLE conversations ALTER COLUMN id SET DEFAULT nextval('conversations_id_seq'::regclass)")
    end
  end
end
