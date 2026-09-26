# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat i/registry endpoints' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def set_item(key, value, scope: %w(client base), domain: nil)
    post '/api/i/registry/set', params: { i: token, scope: scope, domain: domain, key: key, value: value }, as: :json
  end

  describe 'set / get round-trip' do
    it 'stores and returns arbitrary JSON values by type' do
      set_item('darkMode', true)
      expect(response).to have_http_status(204)

      set_item('widgets', [{ 'id' => 'a' }])
      set_item('lang', 'ja')

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'lang' }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('ja')

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'widgets' }, as: :json
      expect(response.parsed_body).to eq([{ 'id' => 'a' }])
    end

    it 'overwrites an existing key rather than duplicating it' do
      set_item('lang', 'ja')
      set_item('lang', 'en')

      expect(account.misskey_registry_items.where(scope: %w(client base), key: 'lang').count).to eq(1)

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'lang' }, as: :json
      expect(response.parsed_body).to eq('en')
    end
  end

  describe 'get on a missing key' do
    it 'returns NO_SUCH_KEY' do
      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'nope' }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig('error', 'code')).to eq('NO_SUCH_KEY')
    end
  end

  describe 'get-all / keys / keys-with-type' do
    before do
      set_item('darkMode', true)
      set_item('count', 3)
      set_item('nullable', nil)
    end

    it 'get-all returns a key->value object scoped correctly' do
      post '/api/i/registry/get-all', params: { i: token, scope: %w(client base) }, as: :json
      expect(response.parsed_body).to eq('darkMode' => true, 'count' => 3, 'nullable' => nil)
    end

    it 'keys returns just the key names' do
      post '/api/i/registry/keys', params: { i: token, scope: %w(client base) }, as: :json
      expect(response.parsed_body).to contain_exactly('darkMode', 'count', 'nullable')
    end

    it 'keys-with-type reports the JSON type of each value' do
      post '/api/i/registry/keys-with-type', params: { i: token, scope: %w(client base) }, as: :json
      expect(response.parsed_body).to eq('darkMode' => 'boolean', 'count' => 'number', 'nullable' => 'null')
    end
  end

  describe 'get-detail' do
    it 'returns updatedAt and value' do
      set_item('lang', 'ja')
      post '/api/i/registry/get-detail', params: { i: token, scope: %w(client base), key: 'lang' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body['value']).to eq('ja')
      expect(response.parsed_body['updatedAt']).to be_present
    end
  end

  describe 'remove' do
    it 'deletes the key and 204s, then get returns NO_SUCH_KEY' do
      set_item('lang', 'ja')

      post '/api/i/registry/remove', params: { i: token, scope: %w(client base), key: 'lang' }, as: :json
      expect(response).to have_http_status(204)

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'lang' }, as: :json
      expect(response).to have_http_status(404)
    end

    it 'returns NO_SUCH_KEY when removing a missing key' do
      post '/api/i/registry/remove', params: { i: token, scope: %w(client base), key: 'nope' }, as: :json
      expect(response).to have_http_status(404)
    end
  end

  describe 'scope and domain isolation' do
    it 'keeps different scopes and domains separate' do
      set_item('lang', 'ja', scope: %w(client base))
      set_item('lang', 'en', scope: %w(deck))
      set_item('lang', 'fr', domain: 'flareApp', scope: %w(client base))

      post '/api/i/registry/get-all', params: { i: token, scope: %w(client base) }, as: :json
      expect(response.parsed_body).to eq('lang' => 'ja')

      post '/api/i/registry/get-all', params: { i: token, scope: %w(deck) }, as: :json
      expect(response.parsed_body).to eq('lang' => 'en')

      post '/api/i/registry/get-all', params: { i: token, scope: %w(client base), domain: 'flareApp' }, as: :json
      expect(response.parsed_body).to eq('lang' => 'fr')
    end
  end

  describe 'app token realms' do
    let(:first_token) { MisskeyCompat::MiAuth.issue_token(user, name: 'First app', permission: 'read:account,write:account') }
    let(:second_token) { MisskeyCompat::MiAuth.issue_token(user, name: 'Second app', permission: 'read:account,write:account') }

    it 'prevents one app from reading or overwriting another app or the native domain' do
      set_item('shared', 'native')
      post '/api/i/registry/set', params: { i: first_token.token, scope: %w(client base), domain: 'chosen', key: 'shared', value: 'first' }, as: :json
      expect(response).to have_http_status(204)

      post '/api/i/registry/get', params: { i: second_token.token, scope: %w(client base), domain: first_token.id.to_s, key: 'shared' }, as: :json
      expect(response).to have_http_status(404)

      post '/api/i/registry/remove', params: { i: second_token.token, scope: %w(client base), domain: first_token.id.to_s, key: 'shared' }, as: :json
      expect(response).to have_http_status(404)

      post '/api/i/registry/set', params: { i: second_token.token, scope: %w(client base), domain: first_token.id.to_s, key: 'shared', value: 'second' }, as: :json
      expect(response).to have_http_status(204)

      post '/api/i/registry/get', params: { i: first_token.token, scope: %w(client base), domain: second_token.id.to_s, key: 'shared' }, as: :json
      expect(response.parsed_body).to eq('first')

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'shared' }, as: :json
      expect(response.parsed_body).to eq('native')

      expect(account.misskey_registry_items.where(key: 'shared').pluck(:access_token_id, :domain, :value)).to contain_exactly(
        [nil, nil, 'native'],
        [first_token.id, first_token.id.to_s, 'first'],
        [second_token.id, second_token.id.to_s, 'second']
      )
    end

    it 'does not expose a legacy arbitrary domain that matches an app token id' do
      account.misskey_registry_items.create!(domain: first_token.id.to_s, scope: %w(client base), key: 'legacy', value: 'old')

      post '/api/i/registry/get', params: { i: first_token.token, scope: %w(client base), domain: first_token.id.to_s, key: 'legacy' }, as: :json
      expect(response).to have_http_status(404)

      post '/api/i/registry/set', params: { i: first_token.token, scope: %w(client base), key: 'legacy', value: 'new' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.misskey_registry_items.where(domain: first_token.id.to_s, key: 'legacy').pluck(:access_token_id, :value)).to contain_exactly(
        [nil, 'old'], [first_token.id, 'new']
      )
    end

    it 'lets a native token inspect an app token domain' do
      post '/api/i/registry/set', params: { i: first_token.token, scope: %w(client base), key: 'appSetting', value: true }, as: :json

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), domain: first_token.id.to_s, key: 'appSetting' }, as: :json
      expect(response.parsed_body).to be(true)
    end
  end

  describe 'scopes-with-domain' do
    it 'lists every stored (domain, scopes) pair' do
      set_item('lang', 'ja', scope: %w(client base))
      set_item('x', 1, scope: %w(deck))
      set_item('y', 2, domain: 'flareApp', scope: %w(client base))

      post '/api/i/registry/scopes-with-domain', params: { i: token }, as: :json
      body = response.parsed_body

      null_entry = body.find { |e| e['domain'].nil? }
      flare_entry = body.find { |e| e['domain'] == 'flareApp' }

      expect(null_entry['scopes']).to contain_exactly(%w(client base), %w(deck))
      expect(flare_entry['scopes']).to eq([%w(client base)])
    end

    it 'denies MiAuth and ordinary OAuth app tokens even when they have account-read permission' do
      app_token = MisskeyCompat::MiAuth.issue_token(user, name: 'Misskey web sign-in', permissions: MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
      oauth_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write')

      [app_token.token, oauth_token.token].each do |credential|
        post '/api/i/registry/scopes-with-domain', params: { i: credential }, as: :json
        expect(response).to have_http_status(403)
        expect(response.parsed_body.dig('error', 'code')).to eq('ACCESS_DENIED')
      end
    end
  end

  describe 'validation and auth' do
    it 'rejects scope items that are not identifier-safe' do
      post '/api/i/registry/get-all', params: { i: token, scope: ['bad scope!'] }, as: :json
      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
    end

    it 'requires authentication' do
      post '/api/i/registry/get-all', params: { scope: %w(client base) }, as: :json
      expect(response).to have_http_status(401)
    end

    it 'rejects oversized registry values' do
      set_item('large', 'x' * (Api::MisskeyCompat::RegistryController::MAX_VALUE_BYTES + 1))

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
      expect(account.misskey_registry_items).to_not exist
    end

    it 'rejects a new write when legacy data already exceeds the account quota' do
      item = account.misskey_registry_items.create!(domain: nil, scope: %w(other), key: 'legacy', value: 'small')
      item.update_column(:value, 'x' * MisskeyRegistryItem::MAX_ACCOUNT_BYTES)

      set_item('new', 'value')

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
      expect(account.misskey_registry_items).to_not exist(key: 'new')
    end

    it 'refuses to aggregate an oversized legacy scope' do
      item = account.misskey_registry_items.create!(domain: nil, scope: %w(client base), key: 'legacy', value: 'small')
      item.update_column(:value, 'x' * MisskeyRegistryItem::MAX_SCOPE_BYTES)

      post '/api/i/registry/get-all', params: { i: token, scope: %w(client base) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('REGISTRY_SCOPE_TOO_LARGE')

      post '/api/i/registry/keys', params: { i: token, scope: %w(client base) }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq(['legacy'])
    end

    it 'enforces a dedicated per-account request limit' do
      RateLimiter::FAMILIES[:misskey_registry][:limit].times do
        RateLimiter.new(account, family: :misskey_registry).record!
      end

      post '/api/i/registry/get', params: { i: token, scope: %w(client base), key: 'lang' }, as: :json

      expect(response).to have_http_status(429)
      expect(response.parsed_body.dig(:error, :code)).to eq('RATE_LIMIT_EXCEEDED')
    end
  end
end
