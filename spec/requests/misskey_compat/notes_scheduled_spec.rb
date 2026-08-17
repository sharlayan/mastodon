# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/scheduled/list' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  it 'rejects offsets above the query budget before loading scheduled statuses' do
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      post '/api/notes/scheduled/list', params: { i: token, offset: 1_001 }, as: :json
    end

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/offset')
    expect(queries.grep(/FROM "scheduled_statuses"/)).to be_empty
  end

  it 'normalizes a negative offset to the first page' do
    scheduled = Fabricate(:scheduled_status, account: user.account)

    post '/api/notes/scheduled/list', params: { i: token, offset: -1 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(scheduled.id))
  end
end
