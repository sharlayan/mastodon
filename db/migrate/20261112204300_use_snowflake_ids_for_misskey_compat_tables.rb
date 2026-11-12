# frozen_string_literal: true

class UseSnowflakeIdsForMisskeyCompatTables < ActiveRecord::Migration[8.1]
  TABLES = %w(
    misskey_abuse_report_recipients misskey_abuse_report_resolutions misskey_achievements misskey_ads
    misskey_apps misskey_auth_sessions misskey_bubble_game_records misskey_channel_favorites
    misskey_channel_followings misskey_channel_mutings misskey_channel_notes misskey_channels
    misskey_flash_likes misskey_flashes misskey_gallery_likes misskey_gallery_posts
    misskey_promo_notes misskey_reversi_games misskey_system_webhooks misskey_user_list_favorites
    misskey_user_list_settings misskey_user_page_views misskey_webhooks
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
