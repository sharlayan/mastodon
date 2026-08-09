# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Roleplay RSS' do
  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  let(:user) { Fabricate(:user) }

  before do
    user.settings[:norss] = false
    user.save!
  end

  it 'disables RSS even when the user setting was enabled' do
    status = Fabricate(:status, account: user.account, text: 'Roleplay RSS status')

    get short_account_path(username: user.account.username)

    expect(response.parsed_body.css('[type="application/rss+xml"]')).to be_empty

    get short_account_path(username: user.account.username), as: :rss

    expect(response.body).to_not include(status.text)
  end
end
