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

  it 'attributes follow-accepted notifications to the followed account' do
    follow = Fabricate(:follow)
    notification = Fabricate.build(:notification, type: :follow_accepted, activity: follow)

    expect(notification.from_account).to eq(follow.target_account)
  end
end
