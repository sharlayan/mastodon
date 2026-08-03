# frozen_string_literal: true

# == Schema Information
#
# Table name: page_daily_statistics
#
#  id                  :bigint(8)        not null, primary key
#  activity_date       :date             not null
#  characters_delta    :integer          default(0), not null
#  pages_created_count :integer          default(0), not null
#  pages_updated_count :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint(8)        not null
#
class PageDailyStatistic < ApplicationRecord
  belongs_to :account

  validates :activity_date, presence: true, uniqueness: { scope: :account_id }

  class << self
    def record!(account_id:, characters_delta: 0, created: 0, updated: 0, activity_date: Time.zone.today)
      upsert(
        {
          account_id: account_id,
          activity_date: activity_date,
          characters_delta: characters_delta,
          pages_created_count: created,
          pages_updated_count: updated,
        },
        unique_by: %i(account_id activity_date),
        on_duplicate: Arel.sql(<<~SQL.squish)
          characters_delta = page_daily_statistics.characters_delta + EXCLUDED.characters_delta,
          pages_created_count = page_daily_statistics.pages_created_count + EXCLUDED.pages_created_count,
          pages_updated_count = page_daily_statistics.pages_updated_count + EXCLUDED.pages_updated_count,
          updated_at = EXCLUDED.updated_at
        SQL
      )
    end
  end

  def activity
    return 'created' if pages_created_count.positive?
    return 'updated' if pages_updated_count.positive?

    'none'
  end
end
