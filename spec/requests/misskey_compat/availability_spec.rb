# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat signup availability endpoints' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def available?(endpoint, **params)
    post "/api/#{endpoint}", params: params, as: :json
    response.parsed_body
  end

  it 'checks usernames against Mastodon uniqueness and reserved names and validates the Misskey pattern' do
    Fabricate(:account, username: 'Taken')
    Fabricate(:username_block, username: 'reserved', exact: true, allow_with_approval: false)

    expect(available?('username/available', username: 'fresh_name')).to eq({ 'available' => true })
    expect(available?('username/available', username: 'taken')).to eq({ 'available' => false })
    expect(available?('username/available', username: 'reserved')).to eq({ 'available' => false })

    available?('username/available', username: 'has-dash')
    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
  end

  it 'checks email addresses against format, existing users and email domain blocks' do
    Fabricate(:user, email: 'used@example.com')
    Fabricate(:email_domain_block, domain: 'blocked.example')

    expect(available?('email-address/available', emailAddress: 'new@example.com')).to eq({ 'available' => true, 'reason' => nil })
    expect(available?('email-address/available', emailAddress: 'not an email')).to eq({ 'available' => false, 'reason' => 'format' })
    expect(available?('email-address/available', emailAddress: 'USED@example.com')).to eq({ 'available' => false, 'reason' => 'used' })
    expect(available?('email-address/available', emailAddress: 'someone@blocked.example')).to eq({ 'available' => false, 'reason' => 'banned' })
  end
end
