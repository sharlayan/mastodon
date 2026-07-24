# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::MisskeyCompat::RetentionAggregationScheduler do
  subject(:worker) { described_class.new }

  before do
    travel_to(Time.utc(2026, 7, 24, 12, 0))
    Setting.misskey_compat_enabled = true
  end

  after { Setting.misskey_compat_enabled = false }

  it 'does nothing when Misskey compatibility is disabled' do
    Setting.misskey_compat_enabled = false

    expect { worker.perform }.to_not change(MisskeyRetentionAggregation, :count)
  end

  it 'records today\'s cohort and fills past cohorts with active retention' do
    user = Fabricate(:user)
    user.account.update_column(:created_at, 1.hour.ago)
    user.update_column(:last_active_at, 30.minutes.ago)

    past = MisskeyRetentionAggregation.create!(
      date_key: '2026-07-20',
      cohort_account_ids: [user.account_id],
      users_count: 1,
      data: {},
      created_at: 4.days.ago,
      updated_at: 4.days.ago
    )

    worker.perform

    today = MisskeyRetentionAggregation.find_by(date_key: '2026-07-24')
    expect(today.users_count).to eq(1)
    expect(today.cohort_account_ids).to include(user.account_id)
    expect(today.data).to eq({})
    expect(past.reload.data['2026-07-24']).to eq(1)
  end

  it 'does not count inactive cohort members as retained' do
    user = Fabricate(:user)
    user.account.update_column(:created_at, 1.hour.ago)
    user.update_column(:last_active_at, 3.days.ago)

    past = MisskeyRetentionAggregation.create!(
      date_key: '2026-07-20', cohort_account_ids: [user.account_id],
      users_count: 1, data: {}, created_at: 4.days.ago, updated_at: 4.days.ago
    )

    worker.perform

    expect(past.reload.data['2026-07-24']).to eq(0)
  end

  it 'skips when today\'s record already exists' do
    MisskeyRetentionAggregation.create!(
      date_key: '2026-07-24', cohort_account_ids: [], users_count: 0,
      data: {}, created_at: Time.current, updated_at: Time.current
    )

    expect { worker.perform }.to_not change(MisskeyRetentionAggregation, :count)
  end
end
