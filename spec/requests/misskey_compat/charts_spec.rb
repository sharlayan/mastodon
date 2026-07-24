# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat charts' do
  before do
    travel_to(Time.utc(2026, 7, 24, 12, 30))
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    Setting.misskey_compat_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
  end

  it 'returns newest-first UTC buckets using the Misskey notes chart shape' do
    account = Fabricate(:account)
    current = Fabricate(:status, account: account, created_at: Time.utc(2026, 7, 24, 12, 10))
    Fabricate(:status, account: account, created_at: Time.utc(2026, 7, 24, 10, 10))
    current.update_columns(deleted_at: Time.utc(2026, 7, 24, 12, 20))

    post '/api/charts/notes', params: { span: 'hour', limit: 3 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.dig(:local, :inc)).to eq([1, 0, 1])
    expect(response.parsed_body.dig(:local, :dec)).to eq([1, 0, 0])
    expect(response.parsed_body.dig(:local, :total)).to eq([1, 1, 1])
    expect(response.parsed_body.dig(:remote, :inc)).to eq([0, 0, 0])
  end

  it 'reuses cached finalized and current buckets without regenerating them' do
    first = MisskeyCompat::ChartService.new(name: :users, span: 'hour', limit: 2).call
    second = MisskeyCompat::ChartService.new(name: :users, span: 'hour', limit: 2)
    allow(second).to receive(:generate).and_call_original

    expect(second.call).to eq(first)
    expect(second).to_not have_received(:generate)
  end

  it 'supports GET and validates the common chart parameters' do
    get '/api/charts/users', params: { span: 'minute', limit: 501 }

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
  end

  it 'advertises all chart endpoints, except Drive charts while Drive is disabled' do
    Setting.drive_enabled = false
    get '/api/endpoints'

    expect(response.parsed_body).to include('charts/notes', 'charts/users', 'charts/user/notes', 'charts/user/pv')
    expect(response.parsed_body).to_not include('charts/drive', 'charts/user/drive')

    post '/api/charts/drive', params: { span: 'day' }, as: :json
    expect(response).to have_http_status(404)
  ensure
    Setting.drive_enabled = false
  end

  it 'returns the stable zero-valued shape for data Mastodon does not retain' do
    post '/api/charts/ap-request', params: { span: 'day', limit: 2 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq(
      'deliverFailed' => [0, 0],
      'deliverSucceeded' => [0, 0],
      'inboxReceived' => [0, 0]
    )
  end

  it 'counts the actual federation domain intersection' do
    local = Fabricate(:account)
    remote = Fabricate(:account, domain: 'remote.example')
    Fabricate(:follow, account: local, target_account: remote)
    Fabricate(:follow, account: remote, target_account: local)

    post '/api/charts/federation', params: { span: 'day', limit: 1 }, as: :json

    expect(response.parsed_body).to include(
      'sub' => [1],
      'pub' => [1],
      'pubsub' => [1]
    )
  end

  it 'generates every supported chart shape' do
    account = Fabricate(:account)
    user_id = MisskeyCompat::MiId.encode(account.id)
    Setting.drive_enabled = true

    requests = %w(active-users drive federation notes users).index_with { {} }
    requests['instance'] = { host: 'remote.example' }
    %w(drive following notes pv reactions).each { |name| requests["user/#{name}"] = { userId: user_id } }

    requests.each do |path, params|
      post "/api/charts/#{path}", params: params.merge(span: 'day', limit: 1), as: :json
      expect(response).to have_http_status(200), "#{path}: #{response.body}"
    end
  ensure
    Setting.drive_enabled = false
  end
end
