# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat antennas' do
  let(:user) { Fabricate(:user) }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }
  let(:antenna) { Fabricate(:antenna, account: user.account) }
  let(:status) { Fabricate(:status) }

  before do
    Setting.misskey_compat_enabled = true
    Setting.antenna_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.antenna_enabled = false
  end

  describe 'POST /api/antennas/create' do
    it 'locks the account while validating the per-account limit' do
      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        post '/api/antennas/create', params: { i: write_token, name: 'bounded antenna', keywords: [%w(test)] }, as: :json
      end

      expect(response).to have_http_status(200)
      expect(queries.any? { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR UPDATE') }).to be(true)
      expect(user.account.antennas.last.with_replies).to be(true)
    end

    it 'preserves the supported client defaults and OR keyword groups' do
      post '/api/antennas/create', params: {
        i: write_token, name: 'supported antenna', src: 'all', keywords: [%w(red), %w(blue)],
        excludeKeywords: [%w(green), %w(yellow)], users: [], caseSensitive: false, localOnly: false,
        excludeBots: false, withReplies: false, withFile: false,
        excludeNotesInSensitiveChannel: false
      }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include('src' => 'all', 'keywords' => [%w(red), %w(blue)], 'excludeKeywords' => [%w(green), %w(yellow)], 'withReplies' => false)
      expect(user.account.antennas.last.keywords).to eq(%w(red blue))
      expect(user.account.antennas.last.exclude_keywords).to eq(%w(green yellow))
      expect(user.account.antennas.last.with_replies).to be(false)
    end

    it 'rejects unsupported sources, options, and AND keyword groups before creating anything' do
      invalid_inputs = [
        { src: 'home' }, { src: 'list', userListId: '123' }, { src: 'unknown' },
        { userListId: '123' }, { localOnly: true }, { excludeBots: true },
        { caseSensitive: true }, { excludeNotesInSensitiveChannel: true },
        { keywords: [%w(red blue)] }, { excludeKeywords: [%w(red blue)] },
        { keywords: %w(red blue) }, { excludeKeywords: [['red', { value: 'blue' }]] }
      ]

      invalid_inputs.each do |input|
        post '/api/antennas/create', params: { i: write_token, name: 'rejected', keywords: [%w(test)] }.merge(input), as: :json

        aggregate_failures(input.inspect) do
          expect(response).to have_http_status(400)
          expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
          expect(user.account.antennas.count).to eq(0)
        end
      end
    end
  end

  describe 'POST /api/antennas/update' do
    it 'updates withReplies only when supplied and returns the stored value' do
      post '/api/antennas/update', params: { i: write_token, antennaId: MisskeyCompat::MiId.encode(antenna.id), name: 'renamed' }, as: :json
      expect(response.parsed_body['withReplies']).to be(true)
      expect(antenna.reload.with_replies).to be(true)

      post '/api/antennas/update', params: { i: write_token, antennaId: MisskeyCompat::MiId.encode(antenna.id), withReplies: false }, as: :json
      expect(response.parsed_body['withReplies']).to be(false)
      expect(antenna.reload.with_replies).to be(false)

      post '/api/antennas/update', params: { i: write_token, antennaId: MisskeyCompat::MiId.encode(antenna.id), name: 'renamed again' }, as: :json
      expect(response.parsed_body['withReplies']).to be(false)
      expect(antenna.reload.with_replies).to be(false)
    end

    it 'leaves the antenna unchanged when a submitted setting is unsupported' do
      antenna.update!(keywords: %w(original), any_keywords: false)
      original = antenna.attributes

      post '/api/antennas/update', params: {
        i: write_token, antennaId: MisskeyCompat::MiId.encode(antenna.id),
        name: 'changed', src: 'users', users: [user.account.acct],
        keywords: [%w(red blue)]
      }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
      expect(antenna.reload.attributes).to eq(original)
      expect(antenna.antenna_accounts.count).to eq(0)
    end
  end

  describe 'POST /api/antennas/list' do
    it 'preserves users, source, and unread state across the collection' do
      user.update!(last_sign_in_at: Time.now.utc)
      included = Fabricate(:account)
      excluded = Fabricate(:account)
      included_antenna = Fabricate(:antenna, account: user.account, any_accounts: false)
      excluded_antenna = Fabricate(:antenna, account: user.account, any_accounts: true, exclude_accounts: [excluded.id.to_s])
      AntennaAccount.create!(antenna: included_antenna, account: included)
      FeedManager.instance.push_to_antenna(included_antenna, Fabricate(:status))

      post '/api/antennas/list', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      by_id = response.parsed_body.index_by { |item| item['id'] }
      expect(by_id.fetch(MisskeyCompat::MiId.encode(included_antenna.id))).to include('src' => 'users', 'users' => [included.acct], 'hasUnreadNote' => true)
      expect(by_id.fetch(MisskeyCompat::MiId.encode(excluded_antenna.id))).to include('src' => 'users_blacklist', 'users' => [excluded.acct], 'hasUnreadNote' => false)
    end

    it 'keeps reversed users arrays consistent with the single-antenna response' do
      lower_account = Fabricate(:account)
      higher_account = Fabricate(:account)
      included_antenna = Fabricate(:antenna, account: user.account, any_accounts: false)
      excluded_antenna = Fabricate(:antenna, account: user.account, any_accounts: true, exclude_accounts: [higher_account.id.to_s, '0', higher_account.id.to_s, lower_account.id.to_s])
      AntennaAccount.create!(antenna: included_antenna, account: higher_account)
      AntennaAccount.create!(antenna: included_antenna, account: lower_account)

      post '/api/antennas/list', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      list_users = response.parsed_body.index_by { |item| item['id'] }
      [included_antenna, excluded_antenna].each do |item|
        post '/api/antennas/show', params: { i: read_token, antennaId: MisskeyCompat::MiId.encode(item.id) }, as: :json

        expect(response).to have_http_status(200)
        expect(list_users.fetch(MisskeyCompat::MiId.encode(item.id)).fetch('users')).to eq(response.parsed_body.fetch('users'))
      end
      expect(list_users.fetch(MisskeyCompat::MiId.encode(excluded_antenna.id)).fetch('users')).to contain_exactly(lower_account.acct, higher_account.acct)
    end
  end

  describe 'feature availability' do
    def each_antenna_action
      encoded_antenna_id = MisskeyCompat::MiId.encode(antenna.id)
      encoded_status_id = MisskeyCompat::MiId.encode(status.id)

      {
        list: {},
        show: { antennaId: encoded_antenna_id },
        create: { name: 'new antenna', keywords: [%w(test)] },
        update: { antennaId: encoded_antenna_id, name: 'updated antenna' },
        delete: { antennaId: encoded_antenna_id },
        notes: { antennaId: encoded_antenna_id },
        'remove-note': { antennaId: encoded_antenna_id, noteId: encoded_status_id },
      }.each do |endpoint, endpoint_params|
        post "/api/antennas/#{endpoint}", params: endpoint_params.merge(i: write_token), as: :json
        yield endpoint
      end
    end

    it 'hides every action when antennas are disabled' do
      Setting.antenna_enabled = false

      each_antenna_action do |endpoint|
        aggregate_failures(endpoint) { expect(response).to have_http_status(404) }
      end
    end

    it 'hides every action in roleplay mode' do
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        each_antenna_action do |endpoint|
          aggregate_failures(endpoint) { expect(response).to have_http_status(404) }
        end
      end
    end
  end
end
