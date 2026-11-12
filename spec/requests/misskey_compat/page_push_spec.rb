# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat page-push endpoint' do
  let(:owner) { Fabricate(:account) }
  let(:user) { Fabricate(:user) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:page) { Fabricate(:page, account: owner) }

  before do
    Setting.misskey_compat_enabled = true
    Setting.pages_enabled = true
    allow(redis).to receive(:exists?).and_call_original
    allow(redis).to receive(:exists?).with("subscribed:misskey:main:#{owner.id}").and_return(true)
    allow(redis).to receive(:publish)
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.pages_enabled = false
  end

  it 'publishes the page event with the pushing user to the page owner main stream' do
    post '/api/page-push', params: { i: token, pageId: MisskeyCompat::MiId.encode(page.id), event: 'clicked', var: { count: 2, list: [1, 'a'] } }, as: :json

    expect(response).to have_http_status(204)
    expect(redis).to have_received(:publish).with("misskey:main:#{owner.id}", satisfy { |message|
      payload = JSON.parse(message)
      payload['event'] == 'main' && payload['payload']['type'] == 'pageEvent' &&
        payload['payload']['body'].slice('pageId', 'event', 'var', 'userId') == { 'pageId' => MisskeyCompat::MiId.encode(page.id), 'event' => 'clicked', 'var' => { 'count' => 2, 'list' => [1, 'a'] }, 'userId' => MisskeyCompat::MiId.encode(user.account_id) } &&
        payload['payload']['body']['user']['username'] == user.account.username
    })
  end

  it 'requires a native token, an event string and a page visible to the caller, and stays silent toward blocked users' do
    app_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token
    post '/api/page-push', params: { i: app_token, pageId: MisskeyCompat::MiId.encode(page.id), event: 'clicked' }, as: :json
    expect(response).to have_http_status(403)

    post '/api/page-push', params: { i: token, pageId: MisskeyCompat::MiId.encode(page.id) }, as: :json
    expect(response).to have_http_status(400)

    private_page = Fabricate(:page, account: owner, visibility: 'private')
    post '/api/page-push', params: { i: token, pageId: MisskeyCompat::MiId.encode(private_page.id), event: 'clicked' }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_PAGE', id: '4a13ad31-6729-46b4-b9af-e86b265c2e74')

    owner.block!(user.account)
    post '/api/page-push', params: { i: token, pageId: MisskeyCompat::MiId.encode(page.id), event: 'clicked' }, as: :json
    expect(response).to have_http_status(204)
    expect(redis).to_not have_received(:publish)
  end
end
