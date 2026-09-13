# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat antennas' do
  let(:user) { Fabricate(:user) }
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
