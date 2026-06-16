# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AccountSwitches' do
  let(:user)        { Fabricate(:user) }
  let(:child_user)  { Fabricate(:user) }
  let(:child)       { child_user.account }

  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:accounts') }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write:accounts') }
  let(:read_headers)  { { 'Authorization' => "Bearer #{read_token.token}" } }
  let(:write_headers) { { 'Authorization' => "Bearer #{write_token.token}" } }

  describe 'GET /api/v1/account_switches' do
    subject { get '/api/v1/account_switches', headers: read_headers }

    context 'with no linked accounts' do
      it 'returns empty children and nil parent' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body[:children]).to be_empty
        expect(response.parsed_body[:parent]).to be_nil
      end
    end

    context 'with a linked child account' do
      before do
        Fabricate(:account_switch_authorization, account: user.account, target_account: child)
      end

      it 'returns the child account' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body[:children].map { |c| c[:target_account][:id] })
          .to contain_exactly(child.id.to_s)
      end
    end

    context 'without authentication' do
      it 'returns 401' do
        get '/api/v1/account_switches'
        expect(response).to have_http_status(401)
      end
    end

    context 'with wrong scope' do
      it 'returns 403' do
        get '/api/v1/account_switches', headers: write_headers
        expect(response).to have_http_status(403)
      end
    end
  end

  describe 'DELETE /api/v1/account_switches/:id' do
    let!(:auth) { Fabricate(:account_switch_authorization, account: user.account, target_account: child) }

    it 'removes the authorization' do
      delete "/api/v1/account_switches/#{auth.id}", headers: write_headers

      expect(response).to have_http_status(200)
      expect { auth.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context 'with wrong scope' do
      it 'returns 403' do
        delete "/api/v1/account_switches/#{auth.id}", headers: read_headers
        expect(response).to have_http_status(403)
      end
    end
  end

  describe 'POST /api/v1/account_switches/push_forward' do
    let!(:auth) { Fabricate(:account_switch_authorization, account: user.account, target_account: child) }

    it 'enables push forwarding' do
      post '/api/v1/account_switches/push_forward',
           headers: write_headers,
           params: { linked_account_id: child.id }

      expect(response).to have_http_status(200)
      expect(auth.reload.push_forward).to be true
    end

    context 'when the account is not linked' do
      it 'returns 404' do
        post '/api/v1/account_switches/push_forward',
             headers: write_headers,
             params: { linked_account_id: 0 }

        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'DELETE /api/v1/account_switches/push_forward' do
    let!(:auth) { Fabricate(:account_switch_authorization, account: user.account, target_account: child, push_forward: true) }

    it 'disables push forwarding' do
      delete '/api/v1/account_switches/push_forward',
             headers: write_headers,
             params: { linked_account_id: child.id }

      expect(response).to have_http_status(200)
      expect(auth.reload.push_forward).to be false
    end
  end
end
