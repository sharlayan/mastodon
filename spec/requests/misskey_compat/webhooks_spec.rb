# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat user webhooks' do
  let(:user)       { Fabricate(:user) }
  let(:account)    { user.account }
  let(:token)      { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:read_token) { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def create_webhook(**params)
    post '/api/i/webhooks/create', params: { i: token, name: 'Hook', url: 'https://hooks.example/a', on: %w(note mention) }.merge(params), as: :json
    response.parsed_body
  end

  describe 'management endpoints' do
    it 'creates, lists, shows, updates and deletes the caller own webhooks' do
      created = create_webhook(secret: 'shh')

      expect(response).to have_http_status(200)
      expect(created).to include(userId: MisskeyCompat::MiId.encode(account.id), name: 'Hook', url: 'https://hooks.example/a', secret: 'shh', on: %w(note mention), active: true, latestSentAt: nil, latestStatus: nil)

      post '/api/i/webhooks/list', params: { i: read_token }, as: :json
      expect(response.parsed_body.pluck(:id)).to eq([created[:id]])

      post '/api/i/webhooks/update', params: { i: token, webhookId: created[:id], secret: nil, active: false, on: %w(follow) }, as: :json
      expect(response).to have_http_status(204)

      post '/api/i/webhooks/show', params: { i: read_token, webhookId: created[:id] }, as: :json
      expect(response.parsed_body).to include(name: 'Hook', secret: '', active: false, on: %w(follow))

      post '/api/i/webhooks/delete', params: { i: token, webhookId: created[:id] }, as: :json
      expect(response).to have_http_status(204)
      expect(MisskeyWebhook.where(account: account)).to be_empty
    end

    it 'hides other accounts webhooks, enforces the limit and validates params' do
      other = MisskeyWebhook.create!(account: Fabricate(:account), name: 'Other', url: 'https://hooks.example/o', events: %w(note))

      %w(show update delete).each do |action|
        post "/api/i/webhooks/#{action}", params: { i: token, webhookId: MisskeyCompat::MiId.encode(other.id) }, as: :json
        expect(response).to have_http_status(404)
        expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_WEBHOOK')
      end

      post '/api/i/webhooks/create', params: { i: read_token, name: 'Hook', url: 'https://hooks.example/a', on: %w(note) }, as: :json
      expect(response).to have_http_status(403)

      [{ on: %w(boost) }, { url: 'ftp://hooks.example' }, { name: '' }, { on: nil }].each do |invalid|
        create_webhook(**invalid)
        expect(response).to have_http_status(400)
      end

      MisskeyWebhook::LIMIT.times { create_webhook }
      expect(create_webhook.dig(:error, :code)).to eq('TOO_MANY_WEBHOOKS')
      expect(MisskeyWebhook.where(account: account).count).to eq(MisskeyWebhook::LIMIT)
    end
  end

  describe 'i/webhooks/test' do
    it 'queues one single-attempt delivery of dummy content with the override, for native tokens only' do
      webhook_id = create_webhook[:id]

      expect do
        post '/api/i/webhooks/test', params: { i: token, webhookId: webhook_id, type: 'renote', override: { url: 'https://hooks.example/b', secret: 'x' } }, as: :json
      end.to enqueue_sidekiq_job(MisskeyCompatWebhookDeliveryWorker).with(MisskeyCompat::MiId.decode(webhook_id), anything, { 'url' => 'https://hooks.example/b', 'secret' => 'x' })
      expect(response).to have_http_status(204)

      job = MisskeyCompatWebhookDeliveryWorker.jobs.last
      expect(job['retry']).to be(false)
      expect(JSON.parse(job['args'][1])).to include('hookId' => webhook_id, 'type' => 'renote', 'body' => include('note' => include('renoteId' => 'dummy-note-1')))

      post '/api/i/webhooks/test', params: { i: token, webhookId: webhook_id, type: 'boost' }, as: :json
      expect(response).to have_http_status(400)

      post '/api/i/webhooks/test', params: { i: read_token, webhookId: webhook_id, type: 'note' }, as: :json
      expect(response).to have_http_status(403)
    end
  end

  describe 'event triggers' do
    let(:author) { Fabricate(:account) }

    before do
      MisskeyWebhook.create!(account: account, name: 'All', url: 'https://hooks.example/all', events: MisskeyWebhook::EVENTS)
    end

    it 'queues note, reply, renote and mention events for the subscribed local accounts' do
      own = Fabricate(:status, account: account)

      expect { Fabricate(:status, account: author, thread: own) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('reply', account.id.to_s, 'Status', anything)
      expect { Fabricate(:status, account: author, reblog: own) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('renote', account.id.to_s, 'Status', anything)
      expect { Fabricate(:status, account: author, mentions: [Fabricate.build(:mention, account: account)]) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('mention', account.id.to_s, 'Status', anything)
      expect { Fabricate(:status, account: account, reblog: own) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('note', account.id.to_s, 'Status', anything).once
      expect { Fabricate(:status, account: author) }.to_not enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker)
    end

    it 'queues follow, followed and unfollow events' do
      expect { account.follow!(author) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('follow', account.id.to_s, 'Account', author.id.to_s)
      expect { author.follow!(account) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('followed', account.id.to_s, 'Account', author.id.to_s)
      expect { account.unfollow!(author) }
        .to enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker).with('unfollow', account.id.to_s, 'Account', author.id.to_s)
    end

    it 'does not queue events while the Misskey compatibility layer is disabled' do
      Setting.misskey_compat_enabled = false

      expect { author.follow!(account) }.to_not enqueue_sidekiq_job(MisskeyCompatWebhookEventWorker)
    end
  end
end
