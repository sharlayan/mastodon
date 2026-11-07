# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmoji do
  let(:status) { Fabricate(:status) }
  let(:emoji) { Fabricate(:custom_emoji, domain: 'remote.example') }
  let(:reactor) { Fabricate(:account, domain: 'remote.example') }
  let!(:reaction) { Fabricate(:status_reaction, status: status, account: reactor, custom_emoji: emoji, name: emoji.shortcode) }

  before do
    Fabricate(:notification, account: status.account, activity: reaction, from_account: reactor, type: :reaction)
  end

  it 'removes reactions with their counters and notifications when destroyed' do
    expect { emoji.destroy! }
      .to change { status.reload.reactions_count }.from(1).to(0)
      .and change(Notification, :count).by(-1)
    expect(StatusReaction.exists?(reaction.id)).to be(false)
  end

  it 'removes reactions with their counters when purged in bulk' do
    expect { AttachmentBatch.new(described_class, [emoji]).delete }
      .to change { status.reload.reactions_count }.from(1).to(0)
      .and change(Notification, :count).by(-1)
  end
end
