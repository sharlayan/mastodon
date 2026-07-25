# frozen_string_literal: true

class Scheduler::MisskeyCompat::RetentionAggregationScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  ACTIVITY_WINDOW = 24.hours

  def perform
    return unless Setting.misskey_compat_enabled

    now = Time.now.utc
    date_key = now.to_date.iso8601

    cohort_account_ids = todays_cohort_account_ids(now)

    return unless insert_todays_cohort(date_key, cohort_account_ids, now)

    active_account_ids = todays_active_account_ids(now).to_set

    update_past_cohorts(date_key, active_account_ids, now)
  end

  private

  def todays_cohort_account_ids(now)
    Account.local
      .where(created_at: (now - ACTIVITY_WINDOW)..now)
      .joins(:user)
      .pluck(:id)
  end

  def todays_active_account_ids(now)
    Account.local
      .joins(:user)
      .where(users: { last_active_at: (now - ACTIVITY_WINDOW)..now })
      .pluck(:id)
  end

  def insert_todays_cohort(date_key, cohort_account_ids, now)
    MisskeyRetentionAggregation.create!(
      date_key: date_key,
      cohort_account_ids: cohort_account_ids,
      users_count: cohort_account_ids.size,
      data: {},
      created_at: now,
      updated_at: now
    )
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end

  def update_past_cohorts(date_key, active_account_ids, now)
    MisskeyRetentionAggregation.recent.where.not(date_key: date_key).find_each do |record|
      retained = record.cohort_account_ids.count { |id| active_account_ids.include?(id) }
      record.update!(data: record.data.merge(date_key => retained), updated_at: now)
    end
  end
end
