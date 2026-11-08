# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Multi-account sign in' do
  let(:source_user) { Fabricate(:user) }
  let(:target_user) { Fabricate(:user, otp_required_for_login: true, otp_secret: User.generate_otp_secret) }
  let(:state) { SecureRandom.hex(16) }

  before do
    MultiAccounts::StateStore.store!(state, SecureRandom.hex(16), source_user.id)
    MultiAccounts::StateStore.update!(state, authenticated_user_id: target_user.id)
  end

  describe 'POST /multi_accounts/auth/verify_otp' do
    it 'stops accepting codes once the hourly two-factor attempt limit is reached' do
      redis.set("2fa_auth_attempts:#{target_user.id}:#{Time.now.utc.hour}", Auth::SessionsController::MAX_2FA_ATTEMPTS_PER_HOUR)

      post '/multi_accounts/auth/verify_otp', params: { state: state, user: { otp_attempt: target_user.current_otp } }

      expect(response.body).to include(I18n.t('users.rate_limited'))
      expect(AccountSwitchAuthorization.exists?(target_account_id: target_user.account_id)).to be(false)
    end

    it 'notifies the owner of a failed two-factor attempt', :inline_jobs do
      emails = capture_emails do
        post '/multi_accounts/auth/verify_otp', params: { state: state, user: { otp_attempt: '000000' } }
      end

      expect(response.body).to include(I18n.t('users.invalid_otp_token'))
      expect(emails.map(&:to)).to eq([[target_user.email]])
    end
  end
end
