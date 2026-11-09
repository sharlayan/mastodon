# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AccountSwitches' do
  let(:user)        { Fabricate(:user) }
  let(:child_user)  { Fabricate(:user) }
  let(:child)       { child_user.account }
  let(:web_app)     { Fabricate(:application, superapp: true) }

  let(:read_token)  { Fabricate(:accessible_access_token, application: web_app, resource_owner_id: user.id, scopes: 'read:accounts') }
  let(:write_token) { Fabricate(:accessible_access_token, application: web_app, resource_owner_id: user.id, scopes: 'write:accounts') }
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
        expect(response.parsed_body[:inbound]).to be_empty
        expect(response.parsed_body[:current_push_forward]).to be_nil
      end
    end

    context 'with a linked child account' do
      before do
        Fabricate(:account_switch_authorization, account: user.account, target_account: child)
      end

      it 'returns the child account without rewriting fresh device metadata on the next read' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body[:children].map { |c| c[:target_account][:id] })
          .to contain_exactly(child.id.to_s)
        expect(response.parsed_body[:children].first).to include(session_authorized: false, session_approval_pending: true)

        device = AccountSwitchDevice.find_by!(account: child)

        expect { get '/api/v1/account_switches', headers: read_headers }
          .to_not(change { device.reload.updated_at })
      end

      it 'does not create approval requests for passive background reads' do
        expect do
          get '/api/v1/account_switches', headers: read_headers, params: { passive: true }
        end.to_not change(AccountSwitchDeviceApproval, :count)

        expect(response.parsed_body[:children].first).to include(session_authorized: false, session_approval_pending: false)
      end

      it 'does not reopen a request the target account just denied' do
        subject
        AccountSwitchDeviceApproval.last.update!(denied_at: Time.current)

        get '/api/v1/account_switches', headers: read_headers

        expect(response.parsed_body[:children].first[:session_approval_pending]).to be false
      end

      it 'reports authorization for only the target account on this session' do
        subject
        AccountSwitchDevice.find_by!(account: child).update!(trusted_at: Time.current)

        get '/api/v1/account_switches', headers: read_headers

        expect(response.parsed_body[:children].first[:session_authorized]).to be true
      end

      it 'bounds untrusted devices retained for an account' do
        10.times do |index|
          child.account_switch_devices.create!(
            token_digest: "old-#{index}",
            first_seen_at: index.days.ago,
            last_seen_at: index.days.ago
          )
        end

        subject

        expect(child.account_switch_devices.where(trusted_at: nil).count).to eq(10)
      end
    end

    it 'rejects missing tokens, tokens with the wrong scope, and tokens that do not belong to the web app' do
      get '/api/v1/account_switches'
      expect(response).to have_http_status(401)

      get '/api/v1/account_switches', headers: write_headers
      expect(response).to have_http_status(403)

      foreign_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:accounts')
      get '/api/v1/account_switches', headers: { 'Authorization' => "Bearer #{foreign_token.token}" }
      expect(response).to have_http_status(403)
    end
  end

  describe 'GET /api/v1/account_switches/linked_unread_counts' do
    let(:second_child_user) { Fabricate(:user) }
    let(:source_account) { Fabricate(:account) }

    before do
      stub_const('Api::V1::AccountSwitchesController::UNREAD_COUNT_LIMIT', 2)
      Fabricate(:account_switch_authorization, account: user.account, target_account: child)
      Fabricate(:account_switch_authorization, account: user.account, target_account: second_child_user.account)

      read_notification = Fabricate(:notification, account: child, activity: Fabricate(:status, account: source_account))
      Fabricate(:marker, user: child_user, timeline: 'notifications', last_read_id: read_notification.id)
      3.times { Fabricate(:notification, account: child, activity: Fabricate(:status, account: source_account)) }
    end

    it 'uses one bounded notification query for all linked accounts' do
      sign_in user
      get root_path
      get '/api/v1/account_switches', headers: read_headers
      child.account_switch_devices.update_all(trusted_at: Time.current)
      second_child_user.account.account_switch_devices.update_all(trusted_at: Time.current)

      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        get '/api/v1/account_switches/linked_unread_counts', headers: read_headers
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq(child.id.to_s => 2, second_child_user.account.id.to_s => 0)
      expect(queries.count { |sql| sql.include?('FROM notifications') }).to eq(1)
      expect(queries.grep(/COUNT\(\*\).*notifications/)).to be_empty
    end

    it 'returns no counts when linked accounts are not authorized for the current device' do
      get '/api/v1/account_switches/linked_unread_counts', headers: read_headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq({})
    end
  end

  describe 'parent account notifications in a switched child session' do
    let(:source_account) { Fabricate(:account) }
    let(:child_session) { child_user.session_activations.order(:id).last }
    let(:child_session_headers) { { 'Authorization' => "Bearer #{child_session.access_token.token}" } }

    before do
      web_app
      Fabricate(:account_switch_authorization, account: user.account, target_account: child)
      sign_in user
      post switch_account_path, params: { switch_to: child.id }
      child_device = AccountSwitchDevice.find_by!(account: child)
      child_device.update!(trusted_at: Time.current)
      AccountSwitchDevice.create!(account: user.account, token_digest: child_device.token_digest, trusted_at: Time.current, first_seen_at: Time.current, last_seen_at: Time.current)
      post switch_account_path, params: { switch_to: child.id }
      2.times { Fabricate(:notification, account: user.account, activity: Fabricate(:status, account: source_account)) }
    end

    it 'reports the parent as authorized and counts its unread notifications for this session only' do
      get '/api/v1/account_switches', headers: child_session_headers, params: { passive: true }

      expect(response.parsed_body[:parent][:id]).to eq user.account.id.to_s
      expect(response.parsed_body[:parent_session_authorized]).to be true

      get '/api/v1/account_switches/linked_unread_counts', headers: child_session_headers

      expect(response.parsed_body).to eq(user.account.id.to_s => 2)
    end

    it 'does not authorize the parent for another session of the child account' do
      other_token = Fabricate(:accessible_access_token, application: web_app, resource_owner_id: child_user.id, scopes: 'read:accounts')
      other_headers = { 'Authorization' => "Bearer #{other_token.token}" }

      get '/api/v1/account_switches', headers: other_headers, params: { passive: true }
      expect(response.parsed_body[:parent_session_authorized]).to be false

      get '/api/v1/account_switches/linked_unread_counts', headers: other_headers
      expect(response.parsed_body).to eq({})
    end

    it 'stops authorizing the parent once the device trust for the parent is revoked' do
      AccountSwitchDevice.find_by!(account: user.account).update!(revoked_at: Time.current)

      get '/api/v1/account_switches', headers: child_session_headers, params: { passive: true }
      expect(response.parsed_body[:parent_session_authorized]).to be false

      get '/api/v1/account_switches/linked_unread_counts', headers: child_session_headers
      expect(response.parsed_body).to eq({})
    end
  end

  describe 'inbound authorizations' do
    let(:linking_user) { Fabricate(:user) }
    let!(:auth) { Fabricate(:account_switch_authorization, account: linking_user.account, target_account: user.account) }

    it 'lists accounts that can switch into the current account' do
      get '/api/v1/account_switches', headers: read_headers

      expect(response.parsed_body[:inbound].map { |item| item.dig(:account, :id) })
        .to contain_exactly(linking_user.account.id.to_s)
    end

    it 'reports push forwarding for the current account while switched into it' do
      auth.update!(push_forward: true)
      sign_in linking_user
      post switch_account_path, params: { switch_to: user.account.id }
      AccountSwitchDevice.find_by!(account: user.account).update!(trusted_at: Time.current)
      post switch_account_path, params: { switch_to: user.account.id }

      get '/api/v1/account_switches', headers: read_headers

      expect(response.parsed_body[:root_account_id]).to eq linking_user.account.id.to_s
      expect(response.parsed_body[:current_push_forward]).to be true
    end

    it 'allows the target account to revoke access' do
      delete "/api/v1/account_switches/#{auth.id}/inbound", headers: write_headers

      expect(response).to have_http_status(200)
      expect(AccountSwitchAuthorization.exists?(auth.id)).to be false
    end

    it 'does not allow a different target to revoke access' do
      other_token = Fabricate(:accessible_access_token, application: web_app, resource_owner_id: child_user.id, scopes: 'write:accounts')

      delete "/api/v1/account_switches/#{auth.id}/inbound", headers: { 'Authorization' => "Bearer #{other_token.token}" }

      expect(response).to have_http_status(404)
      expect(AccountSwitchAuthorization.exists?(auth.id)).to be true
    end

    it 'refuses to revoke the active parent while switched into the target account' do
      sign_in linking_user
      post switch_account_path, params: { switch_to: user.account.id }
      AccountSwitchDevice.find_by!(account: user.account).update!(trusted_at: Time.current)
      post switch_account_path, params: { switch_to: user.account.id }

      delete "/api/v1/account_switches/#{auth.id}/inbound", headers: write_headers

      expect(response).to have_http_status(403)
      expect(AccountSwitchAuthorization.exists?(auth.id)).to be true
    end
  end

  describe 'DELETE /api/v1/account_switches/:id' do
    let!(:auth) { Fabricate(:account_switch_authorization, account: user.account, target_account: child) }

    it 'removes the authorization and pending session approval requests for the unlinked account' do
      get '/api/v1/account_switches', headers: read_headers

      expect do
        delete "/api/v1/account_switches/#{auth.id}", headers: write_headers
      end.to change(AccountSwitchDeviceApproval, :count).by(-1)

      expect(response).to have_http_status(200)
      expect { auth.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'refuses to unlink while switched into a linked account' do
      sign_in user
      post switch_account_path, params: { switch_to: child.id }
      AccountSwitchDevice.find_by!(account: child).update!(trusted_at: Time.current)
      post switch_account_path, params: { switch_to: child.id }
      child_token = Fabricate(:accessible_access_token, application: web_app, resource_owner_id: child_user.id, scopes: 'write:accounts')

      delete "/api/v1/account_switches/#{auth.id}", headers: { 'Authorization' => "Bearer #{child_token.token}" }

      expect(response).to have_http_status(403)
      expect(AccountSwitchAuthorization.exists?(auth.id)).to be true
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
      get '/api/v1/account_switches', headers: read_headers
      AccountSwitchDevice.find_by!(account: child).update!(trusted_at: Time.current)

      post '/api/v1/account_switches/push_forward',
           headers: write_headers,
           params: { linked_account_id: child.id }

      expect(response).to have_http_status(200)
      expect(auth.reload.push_forward).to be true
    end

    it 'refuses a linked account that is not authorized for this session' do
      post '/api/v1/account_switches/push_forward', headers: write_headers, params: { linked_account_id: child.id }

      expect(response).to have_http_status(403)
      expect(auth.reload.push_forward).to be false
    end

    it 'returns 404 for an unlinked account and does not link the root account to itself' do
      post '/api/v1/account_switches/push_forward', headers: write_headers, params: { linked_account_id: 0 }

      expect(response).to have_http_status(404)

      expect do
        post '/api/v1/account_switches/push_forward', headers: write_headers, params: { linked_account_id: user.account.id }
      end.to_not change(AccountSwitchAuthorization, :count)

      expect(response).to have_http_status(404)
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
