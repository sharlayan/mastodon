# frozen_string_literal: true

class UseSnowflakeIdsForChatRecords < ActiveRecord::Migration[8.1]
  TABLES = %w(
    chat_invitations chat_memberships chat_message_edits chat_message_media_attachments
    chat_message_reactions chat_messages chat_roster_states voice_call_allocations
    voice_call_remote_sessions voice_call_remote_states voice_relay_providers
  ).freeze

  def up
    safety_assured do
      TABLES.each do |table|
        next unless table_exists?(table)

        execute("ALTER TABLE #{quote_table_name(table)} ALTER COLUMN id SET DEFAULT timestamp_id(#{connection.quote(table)})")
      end
    end

    Mastodon::Snowflake.ensure_id_sequences_exist
  end

  def down
    safety_assured do
      TABLES.each do |table|
        next unless table_exists?(table)

        execute("ALTER TABLE #{quote_table_name(table)} ALTER COLUMN id SET DEFAULT nextval(#{connection.quote("#{table}_id_seq")}::regclass)")
      end
    end
  end
end
