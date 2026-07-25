# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::MisskeyCompat::FederationStatsScheduler do
  subject(:worker) { described_class.new }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'does nothing when Misskey compatibility is disabled' do
    Setting.misskey_compat_enabled = false

    expect { worker.perform }.to_not change(MisskeyFederationInstanceStat, :count)
  end

  it 'aggregates per-domain user, note and follow counts' do
    local = Fabricate(:account)
    remote = Fabricate(:account, domain: 'remote.example', username: 'bob')
    Fabricate(:status, account: remote)
    Fabricate(:follow, account: local, target_account: remote)

    worker.perform

    stat = MisskeyFederationInstanceStat.find_by(domain: 'remote.example')
    expect(stat).to have_attributes(
      users_count: 1,
      notes_count: 1,
      followers_count: 1, # local users following this instance
      following_count: 0
    )
  end

  it 'counts remote-to-local follows as following_count' do
    local = Fabricate(:account)
    remote = Fabricate(:account, domain: 'remote.example', username: 'carol')
    Fabricate(:follow, account: remote, target_account: local)

    worker.perform

    stat = MisskeyFederationInstanceStat.find_by(domain: 'remote.example')
    expect(stat.following_count).to eq(1)
    expect(stat.followers_count).to eq(0)
  end

  it 'upserts existing rows instead of duplicating them' do
    Fabricate(:account, domain: 'remote.example', username: 'dan')

    worker.perform
    worker.perform

    expect(MisskeyFederationInstanceStat.where(domain: 'remote.example').count).to eq(1)
  end
end
