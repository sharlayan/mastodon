# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inline compose tabs API' do
  include_context 'with API authentication'

  let(:scopes) { 'write:accounts' }

  describe 'PUT /api/v1/inline_compose_tabs' do
    subject do
      put '/api/v1/inline_compose_tabs', headers: headers, params: params, as: :json
    end

    let(:params) do
      { tabs: [{ type: 'list', id: '123' }, { type: 'antenna', id: '456' }] }
    end

    it_behaves_like 'forbidden for wrong scope', 'read read:accounts'

    it 'stores normalized tabs for the current user' do
      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body['tabs']).to eq(params[:tabs].map(&:stringify_keys))
      expect(JSON.parse(user.reload.settings[:inline_compose_tabs])).to eq(params[:tabs].map(&:stringify_keys))
    end

    it 'allows all tabs to be removed' do
      put '/api/v1/inline_compose_tabs', headers: headers, params: { tabs: [] }, as: :json

      expect(response).to have_http_status(200)
      expect(user.reload.settings[:inline_compose_tabs]).to eq('[]')
    end

    context 'with an invalid tab' do
      let(:params) { { tabs: [{ type: 'home', id: '123' }] } }

      it 'returns a bad request without changing settings' do
        expect { subject }.to_not(change { user.reload.settings[:inline_compose_tabs] })

        expect(response).to have_http_status(400)
      end
    end
  end
end
