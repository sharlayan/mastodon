# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Conversations' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses'

  let!(:user) { Fabricate(:user, account_attributes: { username: 'alice' }) }

  let(:other) { Fabricate(:user) }

  describe 'GET /api/v1/conversations', :inline_jobs do
    before do
      user.account.follow!(other.account)
      PostStatusService.new.call(other.account, text: 'Hey @alice', visibility: 'direct')
      PostStatusService.new.call(user.account, text: 'Hey, nobody here', visibility: 'direct')
    end

    it 'returns pagination headers', :aggregate_failures do
      get '/api/v1/conversations', params: { limit: 1 }, headers: headers

      expect(response)
        .to have_http_status(200)
        .and include_pagination_headers(
          prev: api_v1_conversations_url(limit: 1, min_id: Status.first.id),
          next: api_v1_conversations_url(limit: 1, max_id: Status.first.id)
        )
      expect(response.content_type)
        .to start_with('application/json')
    end

    it 'returns conversations', :aggregate_failures do
      get '/api/v1/conversations', headers: headers

      expect(response.parsed_body.size).to eq 2
      expect(response.parsed_body.first[:accounts].size).to eq 1
    end

    context 'with since_id' do
      context 'when requesting old posts' do
        it 'returns conversations' do
          get '/api/v1/conversations', params: { since_id: Mastodon::Snowflake.id_at(1.hour.ago, with_random: false) }, headers: headers

          expect(response.parsed_body.size).to eq 2
        end
      end

      context 'when requesting posts in the future' do
        it 'returns no conversation' do
          get '/api/v1/conversations', params: { since_id: Mastodon::Snowflake.id_at(1.hour.from_now, with_random: false) }, headers: headers

          expect(response.parsed_body.size).to eq 0
        end
      end
    end
  end

  describe 'GET /api/v1/conversations with grouped=1', :inline_jobs do
    before do
      user.account.follow!(other.account)
      PostStatusService.new.call(other.account, text: 'First thread @alice', visibility: 'direct')
      PostStatusService.new.call(other.account, text: 'Second thread @alice', visibility: 'direct')
    end

    it 'collapses threads with the same recipient set into a single card', :aggregate_failures do
      get '/api/v1/conversations', params: { grouped: '1' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq 1
      expect(response.parsed_body.first[:member_ids].size).to eq 2
      expect(response.parsed_body.first[:unread]).to be true
    end
  end

  describe 'GET /api/v1/conversations/:id/statuses', :inline_jobs do
    before do
      user.account.follow!(other.account)
      PostStatusService.new.call(other.account, text: 'First thread @alice', visibility: 'direct')
      PostStatusService.new.call(other.account, text: 'Second thread @alice', visibility: 'direct')
    end

    let(:conversation) { AccountConversation.where(account: user.account).first }

    it 'returns every status across the merged threads in reverse-chronological order', :aggregate_failures do
      get "/api/v1/conversations/#{conversation.id}/statuses", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq 2
      expect(response.parsed_body.pluck(:content).join).to include('First thread', 'Second thread')
      expect(response.parsed_body.first[:id].to_i).to be > response.parsed_body.last[:id].to_i
    end

    it 'generates valid pagination headers including the conversation id', :aggregate_failures do
      get "/api/v1/conversations/#{conversation.id}/statuses", params: { limit: 1 }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.headers['Link']&.to_s).to include("/api/v1/conversations/#{conversation.id}/statuses")
    end
  end

  describe 'GET /api/v1/conversations/with_account/:account_id', :inline_jobs do
    before do
      user.account.follow!(other.account)
      PostStatusService.new.call(other.account, text: 'Hey @alice', visibility: 'direct')
    end

    let(:conversation) { AccountConversation.where(account: user.account).first }

    it 'returns the conversation id for an existing direct conversation', :aggregate_failures do
      get "/api/v1/conversations/with_account/#{other.account.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq conversation.id.to_s
    end

    it 'returns a null id when no conversation exists with the account', :aggregate_failures do
      stranger = Fabricate(:account)

      get "/api/v1/conversations/with_account/#{stranger.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to be_nil
    end
  end
end
