# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sharlayan auth sessions' do
  describe 'GET /auth/sign_in with an account switch target' do
    let(:source_user) { Fabricate(:user) }
    let(:target_user) { Fabricate(:user) }

    before do
      Fabricate(:account_switch_authorization, account: source_user.account, target_account: target_user.account)
      sign_in source_user
    end

    it 'switches directly to an authorized account' do
      expect do
        get new_user_session_path(switch_to: target_user.account_id)
      end.to(change { target_user.reload.current_sign_in_at })

      expect(response).to redirect_to(root_path)
    end

    it 'rejects an unauthorized account' do
      unauthorized_user = Fabricate(:user)

      get new_user_session_path(switch_to: unauthorized_user.account_id)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('account_switcher.switch_unauthorized'))
    end
  end

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
  end
end
