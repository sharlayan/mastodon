# frozen_string_literal: true

class UseSnowflakeIdsForClips < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute(<<~SQL.squish)
        ALTER TABLE clips ALTER COLUMN id SET DEFAULT timestamp_id('clips');
      SQL
    end

    Mastodon::Snowflake.ensure_id_sequences_exist

    migrate_legacy_ids!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Legacy clip IDs are replaced with timestamp-based IDs'
  end

  private

  def migrate_legacy_ids!
    safety_assured do
      execute('LOCK TABLE clips, clip_statuses, clip_favourites IN ACCESS EXCLUSIVE MODE')

      id_mapping = legacy_id_mapping
      return if id_mapping.empty?

      remove_foreign_key :clip_statuses, :clips
      remove_foreign_key :clip_favourites, :clips

      id_mapping.each do |old_id, new_id|
        execute("UPDATE clip_statuses SET clip_id = #{new_id} WHERE clip_id = #{old_id}")
        execute("UPDATE clip_favourites SET clip_id = #{new_id} WHERE clip_id = #{old_id}")
        execute("UPDATE clips SET id = #{new_id} WHERE id = #{old_id}")
      end

      add_foreign_key :clip_statuses, :clips, on_delete: :cascade
      add_foreign_key :clip_favourites, :clips, on_delete: :cascade
    end
  end

  def legacy_id_mapping
    used_ids = Set.new(select_values('SELECT id FROM clips').map(&:to_i))

    select_all('SELECT id, created_at FROM clips').each_with_object({}) do |clip, mapping|
      new_id = Mastodon::Snowflake.id_at(clip['created_at'].to_time)
      new_id = Mastodon::Snowflake.id_at(clip['created_at'].to_time) while used_ids.include?(new_id)

      used_ids << new_id
      mapping[clip['id'].to_i] = new_id
    end
  end
end
