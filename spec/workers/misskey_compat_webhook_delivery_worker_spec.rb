# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompatWebhookDeliveryWorker do
  let(:worker)  { described_class.new }
  let(:webhook) { MisskeyWebhook.create!(account: Fabricate(:account), name: 'Hook', url: 'https://hooks.example/a', secret: 'shh', events: %w(note)) }

  it 'posts the body with Misskey hook headers, honours the test override and records the response status' do
    stub_request(:post, 'https://hooks.example/a').to_return(status: 204)
    stub_request(:post, 'https://hooks.example/b').to_return(status: 404)

    worker.perform(webhook.id.to_s, '{"type":"note"}')

    expect(a_request(:post, 'https://hooks.example/a').with(body: '{"type":"note"}', headers: {
      'Content-Type' => 'application/json',
      'X-Misskey-Host' => Rails.configuration.x.web_domain,
      'X-Misskey-Hook-Id' => MisskeyCompat::MiId.encode(webhook.id),
      'X-Misskey-Hook-Secret' => 'shh',
    })).to have_been_made.once
    expect(webhook.reload).to have_attributes(latest_status: 204, latest_sent_at: be_present)

    worker.perform(webhook.id.to_s, '{}', { 'url' => 'https://hooks.example/b', 'secret' => '' })

    expect(a_request(:post, 'https://hooks.example/b').with(headers: { 'X-Misskey-Hook-Secret' => '' })).to have_been_made.once
    expect(webhook.reload.latest_status).to eq(404)
  end

  it 'raises on retryable responses and records private network targets without retrying' do
    stub_request(:post, 'https://hooks.example/a').to_return(status: 503)

    expect { worker.perform(webhook.id.to_s, '{}') }.to raise_error(Mastodon::UnexpectedResponseError)
    expect(webhook.reload.latest_status).to eq(503)

    expect { worker.perform(webhook.id.to_s, '{}', { 'url' => 'http://127.0.0.1/hook' }) }.to_not raise_error
    expect(webhook.reload.latest_status).to eq(described_class::NETWORK_ERROR_STATUS)
    expect(worker.perform('0', '{}')).to be(true)
  end
end
