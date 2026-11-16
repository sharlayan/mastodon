# frozen_string_literal: true

class UseSnowflakeIdsForChatConversations < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute("ALTER TABLE chat_conversations ALTER COLUMN id SET DEFAULT timestamp_id('chat_conversations')")
    end

    Mastodon::Snowflake.ensure_id_sequences_exist
  end

  def down
    safety_assured do
      execute("ALTER TABLE chat_conversations ALTER COLUMN id SET DEFAULT nextval('chat_conversations_id_seq'::regclass)")
    end
  end
end
