# frozen_string_literal: true

class CleanUpStaleSharlayanSettings < ActiveRecord::Migration[8.1]
  def up
    # DESTRUCTIVE: permanently removes invalid custom emoji mutes and deck columns that reference missing clips.
    # 파괴적: 잘못된 커스텀 에모지 뮤트와 존재하지 않는 클립을 참조하는 덱 컬럼을 영구적으로 삭제합니다.
    safety_assured do
      execute("DELETE FROM custom_emoji_mutes WHERE TRIM(prefix) = ''")
      execute(<<~SQL.squish)
        UPDATE web_settings
        SET data = jsonb_set(
          data::jsonb,
          '{columns}',
          COALESCE(
            (
              SELECT jsonb_agg(deck_column ORDER BY position)
              FROM jsonb_array_elements(data::jsonb->'columns') WITH ORDINALITY AS deck_columns(deck_column, position)
              WHERE deck_column->>'id' IS DISTINCT FROM 'CLIP'
                 OR EXISTS (
                   SELECT 1
                   FROM clips
                   WHERE clips.id::text = deck_column->'params'->>'id'
                 )
            ),
            '[]'::jsonb
          )
        )::json,
        updated_at = CURRENT_TIMESTAMP
        WHERE jsonb_typeof(data::jsonb->'columns') = 'array'
          AND EXISTS (
            SELECT 1
            FROM jsonb_array_elements(data::jsonb->'columns') AS deck_columns(deck_column)
            WHERE deck_column->>'id' = 'CLIP'
              AND NOT EXISTS (
                SELECT 1
                FROM clips
                WHERE clips.id::text = deck_column->'params'->>'id'
              )
          )
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Removed settings cannot be restored'
  end
end
