# frozen_string_literal: true

class UseSnowflakeIdsForSharlayanTables < ActiveRecord::Migration[8.1]
  TABLES = %w(
    status_reactions instance_metadata account_switch_authorizations favorite_emojis
    avatar_decorations avatar_decoration_domain_blocks avatar_decoration_mutes
    avatar_decoration_categories custom_csses reaction_mutes custom_emoji_mutes
    circles circle_accounts circle_statuses board_announcements
    board_announcement_reads board_announcement_attachments
    board_announcement_reactions account_domain_mutes antenna_accounts
    antenna_domains antenna_tags drive_folders drive_files page_likes
    misskey_registry_items clip_favourites drive_file_names page_reports
    misskey_access_grants status_drafts misskey_retention_aggregations
    misskey_federation_instance_stats rp_hidden_statuses
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
