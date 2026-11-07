# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::OmniauthCallbacksController do
  describe '#sign_in_and_redirect' do
    let(:user) { Fabricate(:user) }

    before do
      request.env['devise.mapping'] = Devise.mappings[:user]
      allow(controller).to receive(:redirect_to)
      cookies[:switch_parent_stack] = 'stale'
    end

    it 'clears the account switch stack and trusts the device like a password sign-in' do
      controller.send(:sign_in_and_redirect, user, event: :authentication)

      expect(controller.send(:cookies)[:switch_parent_stack]).to be_nil
      expect(AccountSwitchDevice.trusted.where(account: user.account)).to exist
    end
  end
end
