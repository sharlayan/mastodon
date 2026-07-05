# frozen_string_literal: true

class UseSnowflakeIdsForAntennas < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute(<<~SQL.squish)
        ALTER TABLE antennas ALTER COLUMN id SET DEFAULT timestamp_id('antennas');
      SQL
    end

    Mastodon::Snowflake.ensure_id_sequences_exist
  end

  def down
    execute(<<~SQL.squish)
      LOCK antennas;
      SELECT setval('antennas_id_seq', (SELECT MAX(id) FROM antennas));
      ALTER TABLE antennas ALTER COLUMN id SET DEFAULT nextval('antennas_id_seq');
    SQL
  end
end
