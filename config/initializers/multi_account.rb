# frozen_string_literal: true

Rails.application.configure do
  config.x.multi_account = {
    redirect_uri: ENV.fetch('MA_MULTI_ACCOUNT_REDIRECT_URI') { "#{ENV.fetch('LOCAL_DOMAIN', 'localhost:3000').then { |d| d.start_with?('http') ? d : "https://#{d}" }}/multi_accounts/callback" },
  }
end
