# frozen_string_literal: true

class Scheduler::PageWritingStatisticsScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  RECENT_WINDOW = 2.days

  def perform
    backfill_missing_counts
    reconcile_recent_counts
  end

  private

  def backfill_missing_counts
    Page.where(text_characters_count: nil).find_each do |page|
      page.update_column(:text_characters_count, character_count(page))
    end
  end

  def reconcile_recent_counts
    Page.where(updated_at: RECENT_WINDOW.ago..).where.not(text_characters_count: nil).find_each do |page|
      expected = character_count(page)
      next if expected == page.text_characters_count

      delta = expected - page.text_characters_count
      page.update_column(:text_characters_count, expected)
      PageDailyStatistic.record!(account_id: page.account_id, characters_delta: delta, updated: 1)
    end
  end

  def character_count(page)
    PageTextCharacterCounter.call(summary: page.summary, content: page.content)
  end
end
