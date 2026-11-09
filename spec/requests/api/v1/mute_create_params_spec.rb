# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mute creation with malformed parameters' do
  include_context 'with API authentication', oauth_scopes: 'write:mutes'

  let(:target) { Fabricate(:account) }

  before { Setting.avatar_decorations_enabled = true }

  shared_examples 'a mute endpoint rejecting malformed parameters' do |path|
    it 'rejects an array account id' do
      post path, params: { account_id: [target.id] }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects a domain with a space' do
      post path, params: { domain: 'exa mple.com' }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects a domain with an at sign' do
      post path, params: { domain: 'a@b' }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects an array domain' do
      post path, params: { domain: ['example.com'] }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'still accepts a valid domain' do
      post path, params: { domain: 'Example.com' }, headers: headers

      expect(response).to have_http_status(200)
    end
  end

  describe 'POST /api/v1/reaction_mutes' do
    it_behaves_like 'a mute endpoint rejecting malformed parameters', '/api/v1/reaction_mutes'

    it 'rejects an array acct' do
      post '/api/v1/reaction_mutes', params: { acct: ['someone@example.com'] }, headers: headers

      expect(response).to have_http_status(422)
    end
  end

  describe 'POST /api/v1/avatar_decoration_mutes' do
    it_behaves_like 'a mute endpoint rejecting malformed parameters', '/api/v1/avatar_decoration_mutes'
  end

  describe 'POST /api/v1/custom_emoji_mutes' do
    it 'rejects a domain with a space' do
      post '/api/v1/custom_emoji_mutes', params: { prefix: 'blob', domain: 'exa mple.com' }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects an array domain' do
      post '/api/v1/custom_emoji_mutes', params: { prefix: 'blob', domain: ['example.com'] }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects an array prefix' do
      post '/api/v1/custom_emoji_mutes', params: { prefix: ['blob'] }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'still accepts a valid domain' do
      post '/api/v1/custom_emoji_mutes', params: { prefix: 'blob', domain: 'Example.com' }, headers: headers

      expect(response).to have_http_status(200)
    end
  end
end
