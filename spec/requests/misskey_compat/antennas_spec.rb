# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat antennas' do
  let(:user) { Fabricate(:user) }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

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
end
