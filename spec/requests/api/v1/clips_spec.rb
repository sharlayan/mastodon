# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Clips' do
  include_context 'with API authentication', oauth_scopes: 'write:lists'

  before { Setting.clips_enabled = true }
  after { Setting.clips_enabled = false }

  describe 'POST /api/v1/clips' do
    it 'locks the account while validating the per-account limit' do
      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        post '/api/v1/clips', headers: headers, params: { title: 'bounded clip' }
      end

      expect(response).to have_http_status(200)
      expect(queries.any? { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR UPDATE') }).to be(true)
    end
  end
end
