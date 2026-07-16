# frozen_string_literal: true

class UseSnowflakeIdsForPages < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute(<<~SQL.squish)
        ALTER TABLE pages ALTER COLUMN id SET DEFAULT timestamp_id('pages');
      SQL
    end

    Mastodon::Snowflake.ensure_id_sequences_exist
  end

  def down
    execute(<<~SQL.squish)
      LOCK pages;
      SELECT setval('pages_id_seq', (SELECT MAX(id) FROM pages));
      ALTER TABLE pages ALTER COLUMN id SET DEFAULT nextval('pages_id_seq');
    SQL
  end
end
