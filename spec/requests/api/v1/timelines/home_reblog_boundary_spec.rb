# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Home timeline reblog boundary pagination' do
  subject do
    get '/api/v1/timelines/home', headers: headers, params: { max_id: original.id, limit: 5 }
  end

  let(:user)       { Fabricate(:user) }
  let(:token)      { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses') }
  let(:user_agent) { 'Tusky/27.0 Android/13' }
  let(:headers)    { { 'Authorization' => "Bearer #{token.token}", 'User-Agent' => user_agent } }
  let(:bob)        { Fabricate(:account) }

  let!(:original) { Fabricate(:status, account: bob) }
  let!(:between)  { Fabricate(:status, account: bob) }
  let!(:reblog)   { Fabricate(:status, account: bob, reblog: original) }

  let(:body_ids) { response.parsed_body.pluck(:id) }

  before do
    user.account.follow!(bob)
    FeedManager.instance.populate_home(user.account)
  end

  context 'when the client paginates by the actionable id of a reblog' do
    it 'continues from the feed position of the reblog' do
      subject

      expect(response).to have_http_status(200)
      expect(body_ids).to include(between.id.to_s)
    end
  end

  context 'when the client is not known to paginate by actionable ids' do
    let(:user_agent) { 'Mastodon/4.5.0' }

    it 'keeps the requested boundary' do
      subject

      expect(response).to have_http_status(200)
      expect(body_ids).to_not include(between.id.to_s)
    end
  end

  context 'when min_id is used' do
    subject do
      get '/api/v1/timelines/home', headers: headers, params: { min_id: original.id, max_id: reblog.id, limit: 5 }
    end

    it 'keeps the requested boundaries' do
      subject

      expect(response).to have_http_status(200)
      expect(body_ids).to eq [between.id.to_s]
    end
  end
end
