# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarkStatusesReadService do
  subject { described_class.new }

  let(:reader) { Fabricate(:user).account }
  let(:local_sender) { Fabricate(:user).account }
  let(:remote_sender) { Fabricate(:account, domain: 'remote.example') }
  let(:local_status) { Fabricate(:status, account: local_sender, visibility: :direct) }
  let(:remote_status) { Fabricate(:status, account: remote_sender, visibility: :direct) }

  before do
    Fabricate(:mention, status: local_status, account: reader)
    Fabricate(:mention, status: remote_status, account: reader)
  end

  it 'idempotently records receipts only for direct messages from local accounts that mention the reader' do
    unmentioned = Fabricate(:status, account: local_sender, visibility: :direct)

    2.times { subject.call(reader, [local_status.id, remote_status.id, unmentioned.id]) }

    expect(StatusReadReceipt.pluck(:status_id, :account_id)).to contain_exactly([local_status.id, reader.id])
  end

  it 'publishes newly-created receipts to the local sender stream' do
    redis = instance_spy(Redis)

    described_class.new(redis: redis).call(reader, [local_status.id])

    expect(redis).to have_received(:publish).with("timeline:direct:#{local_sender.id}", include('conversation.read', local_status.id.to_s, reader.id.to_s))
  end
end
