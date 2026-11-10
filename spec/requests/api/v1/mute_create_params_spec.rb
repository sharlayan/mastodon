# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mute creation with malformed parameters' do
  include_context 'with API authentication', oauth_scopes: 'write:mutes'

  let(:target) { Fabricate(:account) }

  before { Setting.avatar_decorations_enabled = true }

  shared_examples 'a mute endpoint rejecting malformed parameters' do |path|
    it 'rejects array account ids and malformed or array domains but still accepts a valid domain', :aggregate_failures do
      [
        { account_id: [target.id] },
        { domain: 'exa mple.com' },
        { domain: 'a@b' },
        { domain: ['example.com'] },
      ].each do |params|
        post path, params: params, headers: headers

        expect(response).to have_http_status(422), -> { "#{params.inspect} returned #{response.status}" }
      end

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
    it 'rejects malformed or array domains and array prefixes but still accepts a valid domain', :aggregate_failures do
      [
        { prefix: 'blob', domain: 'exa mple.com' },
        { prefix: 'blob', domain: ['example.com'] },
        { prefix: ['blob'] },
      ].each do |params|
        post '/api/v1/custom_emoji_mutes', params: params, headers: headers

        expect(response).to have_http_status(422), -> { "#{params.inspect} returned #{response.status}" }
      end

      post '/api/v1/custom_emoji_mutes', params: { prefix: 'blob', domain: 'Example.com' }, headers: headers

      expect(response).to have_http_status(200)
    end
  end
end
