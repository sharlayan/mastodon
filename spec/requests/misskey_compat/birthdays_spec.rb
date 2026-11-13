# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat birthday endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before do
    Setting.misskey_compat_enabled = true
    travel_to(Time.zone.local(2026, 11, 12, 9))
  end

  after { Setting.misskey_compat_enabled = false }

  it 'stores a Misskey birthday, rejects other formats and shows it to others only when the owner allows it' do
    post '/api/i/update', params: { i: token, birthday: '12/31' }, as: :json
    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/birthday')

    post '/api/i/update', params: { i: token, birthday: '2999-01-01' }, as: :json
    expect(response).to have_http_status(400)

    post '/api/i/update', params: { i: token, birthday: '1990-12-31' }, as: :json
    expect(response.parsed_body[:birthday]).to eq('1990-12-31')

    post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
    expect(response.parsed_body[:birthday]).to be_nil

    user.settings['show_birthday'] = true
    user.save!
    post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
    expect(response.parsed_body[:birthday]).to eq('1990-12-31')

    post '/api/i/update', params: { i: token, birthday: nil }, as: :json
    expect(account.reload.birthday).to be_nil
  end

  it 'lists followed users by birthday with year-wrapping ranges, the next occurrence and offset paging' do
    birthdays = { 'nov' => '1990-11-12', 'dec' => '1985-12-31', 'jan' => '2000-01-02', 'oct' => '1999-10-01', 'bad' => 'sometime' }
    followees = birthdays.to_h do |name, birthday|
      followee = Fabricate(:user, account_attributes: { username: name }).account
      followee.user.update!(settings_attributes: { show_birthday: true })
      followee.update_column(:birthday, birthday)
      account.follow!(followee)
      [name, followee]
    end
    hidden = Fabricate(:user, account_attributes: { username: 'hidden', birthday: '1990-11-12' }).account
    account.follow!(hidden)
    Fabricate(:account, username: 'stranger', birthday: '1990-11-12')

    post '/api/users/get-following-users-by-birthday', params: { i: token, birthday: { month: 11, day: 12 } }, as: :json
    expect(response.parsed_body).to eq([{ 'id' => MisskeyCompat::MiId.encode(followees['nov'].id), 'birthday' => '2026-11-12', 'user' => response.parsed_body.first['user'] }])
    expect(response.parsed_body.first['user']).to include('username' => 'nov')

    post '/api/users/get-following-users-by-birthday', params: { i: token, birthday: { begin: { month: 12, day: 1 }, end: { month: 1, day: 31 } } }, as: :json
    expect(response.parsed_body.map { |item| [item['user']['username'], item['birthday']] }).to eq([%w(jan 2027-01-02), %w(dec 2026-12-31)])

    post '/api/users/get-following-users-by-birthday', params: { i: token, birthday: { begin: { month: 1, day: 1 }, end: { month: 12, day: 31 } }, limit: 1, offset: 1 }, as: :json
    expect(response.parsed_body.map { |item| [item['user']['username'], item['birthday']] }).to eq([%w(oct 2027-10-01)])

    post '/api/users/get-following-users-by-birthday', params: { i: token, birthday: { month: 13, day: 1 } }, as: :json
    expect(response).to have_http_status(400)
  end
end
