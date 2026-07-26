# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RedownloadAvatarDecorationWorker do
  subject(:worker) { described_class.new }

  let(:image) { Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').read }
  let(:account) { Fabricate(:account, domain: 'remote.example') }

  before do
    stub_request(:get, %r{\Ahttps://remote\.example/})
      .to_return(status: 200, body: image, headers: { 'Content-Type' => 'image/png' })
  end

  describe '.enqueue' do
    it 'deduplicates the same decoration URL' do
      decoration = remote_decoration('one')
      allow(described_class).to receive(:perform_async)
      key = described_class.deduplication_key(decoration)

      expect(described_class.enqueue(decoration.id, account_id: account.id)).to be true
      expect(described_class.enqueue(decoration.id, account_id: account.id)).to be false
      expect(described_class).to have_received(:perform_async).once
    ensure
      RedisConnection.with { |redis| redis.del(key) } if key
    end
  end

  it 'downloads a remote decoration only in the worker' do
    decoration = remote_decoration('one')

    expect { worker.perform(decoration.id, account.id) }
      .to change { decoration.reload.image_file_name.present? }.from(false).to(true)
  end

  it 'enforces the hourly account download budget' do
    stub_const("#{described_class}::ACCOUNT_LIMIT", 1)
    first = remote_decoration('one')
    second = remote_decoration('two')

    worker.perform(first.id, account.id)
    worker.perform(second.id, account.id)

    expect(first.reload.image_file_name).to be_present
    expect(second.reload.image_file_name).to be_blank
  ensure
    bucket = Time.now.to_i / described_class::BUDGET_PERIOD
    RedisConnection.with do |redis|
      redis.del(
        "avatar_decoration_download:domain:remote.example:#{bucket}",
        "avatar_decoration_download:account:#{account.id}:#{bucket}"
      )
    end
  end

  def remote_decoration(id)
    Fabricate(
      :avatar_decoration,
      host: 'remote.example',
      remote_id: id,
      image_remote_url: "https://remote.example/#{id}.png",
      image: nil
    )
  end
end
