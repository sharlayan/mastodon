# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pages in roleplay mode' do
  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  before { Setting.pages_enabled = true }

  it 'requires a logged-in user for public page endpoints' do
    account = Fabricate(:account)

    get "/api/v1/accounts/#{account.id}/pages"

    expect(response.status).to be_between(400, 499)

    get '/api/v1/pages/featured'

    expect(response.status).to be_between(400, 499)

    post '/api/misskey/pages/featured'

    expect(response.status).to be_between(400, 499)
  end
end
