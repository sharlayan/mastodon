# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification do
  it 'registers reaction and follow-accepted notification contracts' do
    expect(described_class::LEGACY_TYPE_CLASS_MAP['StatusReaction']).to eq(:reaction)
    expect(described_class::PROPERTIES).to include(reaction: include(filterable: true), follow_accepted: include(filterable: false))
    expect(described_class::TARGET_STATUS_INCLUDES_BY_TYPE).to include(reaction: [status_reaction: [:status, :custom_emoji]])
  end

  it 'exposes a reaction target through both association names' do
    reaction = Fabricate(:status_reaction)
    notification = Fabricate.build(:notification, type: :reaction, activity: reaction)

    expect(notification.reaction).to eq(reaction)
    expect(notification.target_status).to eq(reaction.status)
  end

  it 'resolves the notification type from a reaction activity' do
    status = Fabricate(:status)
    reaction = Fabricate(:status_reaction, status: status)

    expect(described_class.new(activity: StatusReaction.new).type).to eq(:reaction)
    expect(described_class.new(activity: reaction).target_status).to eq(status)
  end

  it 'preloads reaction target statuses with their associations' do
    reaction = Fabricate(:status_reaction)
    notification = Fabricate(:notification, type: :reaction, activity: reaction)

    preloaded = described_class.preload_cache_collection_target_statuses([notification]) do |target_statuses|
      Status.preload(:account).where(id: target_statuses.map(&:id))
    end

    expect(preloaded.first).to have_attributes(
      type: :reaction,
      status_reaction: have_loaded_association(:status),
      target_status: eq(reaction.status).and(have_loaded_association(:account))
    ).and(have_loaded_association(:status_reaction))
  end

  it 'attributes follow-accepted notifications to the followed account' do
    follow = Fabricate(:follow)
    notification = Fabricate.build(:notification, type: :follow_accepted, activity: follow)

    expect(notification.from_account).to eq(follow.target_account)
  end
end
