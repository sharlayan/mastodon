# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::SerializationContext do
  it 'preloads an embedded status when a root has the same database ID through another object' do
    parent = Fabricate(:status)
    mentioned = Fabricate(:account)
    Fabricate(:mention, status: parent, account: mentioned)
    child = Fabricate(:status, in_reply_to_id: parent.id, in_reply_to_account_id: parent.account_id)

    root_parent = Status.find(parent.id)
    root_child = Status.find(child.id)
    embedded_parent = root_child.thread

    expect(embedded_parent).to_not equal(root_parent)
    expect(embedded_parent.association(:mentions)).to_not be_loaded

    described_class.for([root_parent, root_child])

    expect(embedded_parent.association(:mentions)).to be_loaded
    expect(embedded_parent.mentions.first.association(:account)).to be_loaded
  end

  describe '#visible?' do
    let(:viewer) { Fabricate(:account) }
    let(:blocker) { Fabricate(:account) }
    let(:friend) { Fabricate(:account) }

    before { blocker.block!(viewer) }

    it 'hides posts from authors who block the viewer using preloaded relations' do
      blocked_status = Fabricate(:status, account: blocker)
      visible_status = Fabricate(:status, account: friend)
      context = described_class.new(current_account: viewer).prime_relations([blocked_status, visible_status])

      expect(context.visible?(blocked_status)).to be false
      expect(context.visible?(visible_status)).to be true
    end

    it 'checks authors outside the preloaded set against the database' do
      visible_status = Fabricate(:status, account: friend)
      blocked_status = Fabricate(:status, account: blocker)
      context = described_class.new(current_account: viewer).prime_relations([visible_status])

      expect(context.visible?(blocked_status)).to be false
    end

    it 'does not leave preloaded relations on the viewer account' do
      status = Fabricate(:status, account: friend)
      described_class.new(current_account: viewer).prime_relations([status])

      expect(viewer.blocked_by?(blocker)).to be true
    end
  end
end
