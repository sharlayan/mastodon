# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Log Out' do
  include RoutingHelper

  describe 'DELETE /auth/sign_out' do
    let(:user) { Fabricate(:user) }

    before do
      sign_in user
    end

    it 'Logs out the user and redirect' do
      delete '/auth/sign_out'

      expect(response).to redirect_to('/auth/sign_in')
    end

    it 'Logs out the user and return a page to redirect to with a JSON request' do
      delete '/auth/sign_out', headers: { 'HTTP_ACCEPT' => 'application/json' }

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq 'application/json'

      expect(response.parsed_body[:redirect_to]).to eq '/auth/sign_in'
    end

    context 'when switched into a linked account' do
      let(:linked_user) { Fabricate(:user) }

      before do
        Fabricate(:account_switch_authorization, account: user.account, target_account: linked_user.account)
        post switch_account_path, params: { switch_to: linked_user.account.id }
        AccountSwitchDevice.find_by!(account: linked_user.account).update!(trusted_at: Time.current)
        post switch_account_path, params: { switch_to: linked_user.account.id }
      end

      it 'returns to the main account instead of logging out' do
        delete '/auth/sign_out'

        expect(response).to redirect_to(root_path)
        expect(cookies[:switch_parent_stack]).to be_blank

        post switch_account_path, params: { switch_to: linked_user.account.id }
        expect(response).to redirect_to(root_path)
        expect(cookies[:switch_parent_stack]).to be_present
      end

      it 'returns the main page redirect with a JSON request' do
        delete '/auth/sign_out', headers: { 'HTTP_ACCEPT' => 'application/json' }

        expect(response).to have_http_status(200)
        expect(response.media_type).to eq 'application/json'
        expect(response.parsed_body[:redirect_to]).to eq root_path
        expect(cookies[:switch_parent_stack]).to be_blank
      end
    end
  end
end
