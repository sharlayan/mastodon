# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat achievement endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'claims only Misskey achievement names once, notifies the owner and lists them publicly in unlock order' do
    post '/api/i/claim-achievement', params: { i: read_token, name: 'notes1' }, as: :json
    expect(response).to have_http_status(403)

    post '/api/i/claim-achievement', params: { i: token, name: 'sharlayan' }, as: :json
    expect(response).to have_http_status(400)

    travel_to(Time.utc(2026, 11, 1, 0, 0, 0)) { post '/api/i/claim-achievement', params: { i: token, name: 'tutorialCompleted' }, as: :json }
    expect(response).to have_http_status(204)
    travel_to(Time.utc(2026, 11, 2, 0, 0, 0)) do
      post '/api/i/claim-achievement', params: { i: token, name: 'iLoveMisskey' }, as: :json
      post '/api/i/claim-achievement', params: { i: token, name: 'tutorialCompleted' }, as: :json
    end

    post '/api/users/achievements', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
    expect(response.parsed_body).to eq([
                                         { 'name' => 'tutorialCompleted', 'unlockedAt' => Time.utc(2026, 11, 1).to_i * 1000 },
                                         { 'name' => 'iLoveMisskey', 'unlockedAt' => Time.utc(2026, 11, 2).to_i * 1000 },
                                       ])
    expect(MisskeyNotification.where(account: account, notification_type: 'achievementEarned').pluck(Arel.sql("data->>'achievement'"))).to contain_exactly('tutorialCompleted', 'iLoveMisskey')

    post '/api/i', params: { i: token }, as: :json
    expect(response.parsed_body[:achievements].pluck(:name)).to eq(%w(tutorialCompleted iLoveMisskey))

    post '/api/users/achievements', params: { userId: '0000000000000000' }, as: :json
    expect(response).to have_http_status(404)
  end

  it 'lists achievements for native and account-reading MiAuth tokens while rejecting other app permissions' do
    MisskeyAchievement.unlock!(account, 'notes1')
    tokens = [
      MisskeyCompat::MiAuth.issue_native_token(user).token,
      MisskeyCompat::MiAuth.issue_token(user, permissions: ['read:account']).token,
    ]

    tokens.each do |access_token|
      post '/api/users/achievements', params: { i: access_token, userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:name)).to eq(['notes1'])
    end

    app_token = MisskeyCompat::MiAuth.issue_token(user, permissions: ['write:account']).token
    post '/api/users/achievements', params: { i: app_token, userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
  end

  it 'awards myNoteFavorited1 to the local author when someone else favorites the note through the compat API' do
    status = Fabricate(:status, account: account)
    other = Fabricate(:user)
    other_token = Fabricate(:accessible_access_token, resource_owner_id: other.id, scopes: 'read write').token

    post '/api/notes/favorites/create', params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json
    expect(MisskeyAchievement.where(account: account)).to be_empty

    post '/api/notes/favorites/create', params: { i: other_token, noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json
    expect(response).to have_http_status(204)
    expect(MisskeyAchievement.where(account: account).pluck(:name)).to eq(['myNoteFavorited1'])
  end

  it 'rejects claims from moved accounts' do
    account.update!(moved_to_account: Fabricate(:account))

    post '/api/i/claim-achievement', params: { i: token, name: 'notes1' }, as: :json

    expect(response).to have_http_status(403)
    expect(response.parsed_body[:error]).to include(code: 'YOUR_ACCOUNT_MOVED', kind: 'permission')
  end
end
