# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Antennas' do
  include_context 'with API authentication', oauth_scopes: 'read:lists write:lists'

  describe 'GET /api/v1/antennas' do
    subject { get '/api/v1/antennas', headers: headers }

    let!(:antenna) { Fabricate(:antenna, account: user.account, title: 'mine') }

    before { Fabricate(:antenna) } # someone else's

    it 'returns only the current user antennas' do
      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([antenna.id.to_s])
    end
  end

  describe 'POST /api/v1/antennas' do
    subject { post '/api/v1/antennas', headers: headers, params: { title: 'new antenna', keywords: %w(commission) } }

    it 'creates an antenna' do
      expect { subject }.to change(Antenna, :count).by(1)
      expect(response).to have_http_status(200)
      expect(response.parsed_body[:title]).to eq('new antenna')
      expect(response.parsed_body[:keywords]).to eq(%w(commission))
    end
  end

  describe 'PUT /api/v1/antennas/:id' do
    subject { put "/api/v1/antennas/#{antenna.id}", headers: headers, params: { available: false } }

    let(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'updates the antenna' do
      subject

      expect(response).to have_http_status(200)
      expect(antenna.reload.available).to be(false)
    end
  end

  describe 'DELETE /api/v1/antennas/:id' do
    subject { delete "/api/v1/antennas/#{antenna.id}", headers: headers }

    let!(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'deletes the antenna' do
      expect { subject }.to change(Antenna, :count).by(-1)
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST /api/v1/antennas/:id/domains' do
    subject { post "/api/v1/antennas/#{antenna.id}/domains", headers: headers, params: { domains: ['example.com'] } }

    let(:antenna) { Fabricate(:antenna, account: user.account) }

    it 'adds an include domain condition' do
      subject

      expect(response).to have_http_status(200)
      expect(antenna.antenna_domains.includes_only.pluck(:name)).to include('example.com')
    end
  end
end
