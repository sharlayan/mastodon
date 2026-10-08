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
end
