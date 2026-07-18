# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountStatusesCleanupPolicy do
  let(:account) { Fabricate(:account) }
  let(:policy) do
    Fabricate(
      :account_statuses_cleanup_policy,
      account: account,
      keep_direct: false,
      keep_media: false,
      keep_pinned: false,
      keep_polls: false,
      keep_self_bookmark: false,
      keep_self_fav: false,
      keep_self_reaction: true,
      keep_self_clip: true
    )
  end

  it 'keeps old statuses with a self reaction or a self-owned clip' do
    reacted = Fabricate(:status, account: account, created_at: 1.year.ago)
    clipped = Fabricate(:status, account: account, created_at: 1.year.ago)
    deletable = Fabricate(:status, account: account, created_at: 1.year.ago)
    Fabricate(:status_reaction, account: account, status: reacted)
    Fabricate(:clip, account: account).clip_statuses.create!(status: clipped)

    expect(policy.statuses_to_delete.pluck(:id)).to contain_exactly(deletable.id)
  end

  it 'keeps statuses at the configured reaction threshold' do
    below_threshold = Fabricate(:status, account: account, created_at: 1.year.ago)
    at_threshold = Fabricate(:status, account: account, created_at: 1.year.ago)
    below_threshold.status_stat.update!(reactions_count: 4)
    at_threshold.status_stat.update!(reactions_count: 5)
    policy.update!(keep_self_reaction: false, keep_self_clip: false, min_reactions: 5)

    expect(policy.statuses_to_delete.pluck(:id)).to include(below_threshold.id).and not_include(at_threshold.id)
  end

  it 'invalidates the inspected boundary only for enabled Sharlayan exceptions' do
    status = Fabricate(:status, id: 10, account: account)
    policy.record_last_inspected(42)

    policy.invalidate_last_inspected(status, :unreact)
    expect(policy.last_inspected).to eq(10)

    policy.record_last_inspected(42)
    policy.keep_self_clip = false
    policy.invalidate_last_inspected(status, :unclip)
    expect(policy.last_inspected).to eq(42)
  end
end
