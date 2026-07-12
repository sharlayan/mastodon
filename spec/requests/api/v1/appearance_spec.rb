# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Appearance API' do
  include_context 'with API authentication'

  let(:scopes) { 'write:accounts' }

  describe 'PUT /api/v1/appearance' do
    subject do
      put '/api/v1/appearance', headers: headers, params: params
    end

    let(:params) { { color_scheme: 'dark', contrast: 'high' } }

    it_behaves_like 'forbidden for wrong scope', 'read read:accounts'

    it 'updates the current user appearance settings' do
      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq({
        'color_scheme' => 'dark',
        'contrast' => 'high',
      })
      settings = user.reload.settings
      expect(settings['web.color_scheme']).to eq('dark')
      expect(settings['web.contrast']).to eq('high')
    end

    context 'when only one setting is supplied' do
      let(:params) { { color_scheme: 'light' } }

      before do
        user.settings['web.contrast'] = 'high'
        user.save!
      end

      it 'preserves the other setting' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq({
          'color_scheme' => 'light',
          'contrast' => 'high',
        })
      end
    end

    context 'with an invalid setting value' do
      let(:params) { { color_scheme: 'invalid', contrast: 'high' } }

      it 'returns a bad request without changing settings' do
        expect { subject }.to_not(change { user.reload.settings.as_json })

        expect(response).to have_http_status(400)
        expect(response.parsed_body).to include('error' => "Invalid value for 'web.color_scheme'")
      end
    end

    context 'without an access token' do
      it 'returns unauthorized' do
        put '/api/v1/appearance', params: params

        expect(response).to have_http_status(401)
      end
    end
  end
end
