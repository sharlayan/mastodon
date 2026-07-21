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
  end
end
