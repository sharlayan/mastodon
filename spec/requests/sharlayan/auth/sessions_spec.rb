# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sharlayan auth sessions' do
  describe 'POST /auth/sign_in with custom CSS disabled' do
    let(:password) { 'correct horse battery staple' }
    let(:user) { Fabricate(:user, password:, password_confirmation: password) }

    before do
      user.settings['web.use_custom_css'] = true
      user.save!
    end

    it 'turns off the user custom CSS preference' do
      post user_session_path, params: { disable_css: 'true', user: { email: user.email, password: } }

      expect(user.reload.settings['web.use_custom_css']).to be false
    end

    context 'when a security code is required' do
      before do
        user.update!(current_sign_in_at: 95.days.ago)
      end

      it 'preserves the preference through the challenge and trusts the device after signing in' do
        post user_session_path, params: { disable_css: 'true', user: { email: user.email, password: } }

        expect(response.parsed_body.at_css('input[type="hidden"][name="disable_css"]')['value']).to eq('true')
        expect(user.reload.settings['web.use_custom_css']).to be true
        expect(user.account.account_switch_devices).to be_empty

        post user_session_path, params: { disable_css: 'true', user: { sign_in_token_attempt: user.sign_in_token } }

        expect(response).to redirect_to(root_path)
        expect(user.reload.settings['web.use_custom_css']).to be false
        expect(user.account.account_switch_devices.first).to be_trusted
      end
    end
  end
end
