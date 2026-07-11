# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat scratchpad' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }

  let(:endpoint)  { 'https://fcm.googleapis.com/fcm/send/fiuH06a27qE' }
  let(:auth)      { 'eH_C8rq2raXqlcBVDa1gLg==' }
  let(:publickey) { 'BEm_a0bdPDhf0SOsrnB2-ategf1hHoCnpXgQsFj5JCkcoMrMt2WHoPfEYOYPzOIs9mZE8ZUaD7VA5vouy0kEkr8=' }

  def aria_code(username: account.username, url: endpoint)
    <<~CODE
      if (USER_USERNAME != '#{username}') {
        Core:abort(`nope`)
      }
      let params = {
        endpoint: '#{url}',
        auth: '#{auth}',
        publickey: '#{publickey}',
      }
      let response = Mk:api('sw/register', params)
    CODE
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'GET /scratchpad' do
    context 'when misskey compat is disabled' do
      before { Setting.misskey_compat_enabled = false }

      it 'returns 404' do
        sign_in user
        get '/scratchpad'
        expect(response).to have_http_status(404)
      end
    end

    context 'when not signed in' do
      it 'redirects to sign in' do
        get '/scratchpad'
        expect(response).to have_http_status(302)
      end
    end

    context 'when signed in' do
      it 'renders the scratchpad form' do
        sign_in user
        get '/scratchpad'
        expect(response).to have_http_status(200)
        expect(response.body).to include(I18n.t('misskey_compat.scratchpad.run'))
      end
    end
  end

  describe 'POST /scratchpad' do
    before do
      sign_in user
      # Trigger creation of a SessionActivation with an access token
      get about_path
    end

    it 'registers a push subscription and returns the response JSON' do
      expect { post '/scratchpad', params: { code: aria_code } }
        .to change(Web::PushSubscription, :count).by(1)

      expect(response).to have_http_status(200)

      subscription = Web::PushSubscription.find_by(endpoint: endpoint)
      expect(subscription).to have_attributes(user_id: user.id, key_auth: auth, key_p256dh: publickey)
      expect(subscription.data['compat']).to eq('misskey')
      expect(response.body).to include(CGI.escapeHTML('"state":"subscribed"'))
      expect(response.body).to include(CGI.escapeHTML(%("userId":"#{account.id}")))
    end

    it 'reports already-subscribed on repeat' do
      post '/scratchpad', params: { code: aria_code }
      post '/scratchpad', params: { code: aria_code }

      expect(Web::PushSubscription.where(endpoint: endpoint).count).to eq(1)
      expect(response.body).to include(CGI.escapeHTML('"state":"already-subscribed"'))
    end

    it 'refuses code targeting another account' do
      expect { post '/scratchpad', params: { code: aria_code(username: 'someoneelse') } }
        .to_not change(Web::PushSubscription, :count)

      expect(response.body).to include(CGI.escapeHTML(I18n.t('misskey_compat.scratchpad.wrong_account', expected: 'someoneelse', current: account.username)))
    end

    it 'rejects unrecognized code' do
      expect { post '/scratchpad', params: { code: 'let x = 1' } }
        .to_not change(Web::PushSubscription, :count)

      expect(response.body).to include(I18n.t('misskey_compat.scratchpad.unsupported'))
    end
  end
end
