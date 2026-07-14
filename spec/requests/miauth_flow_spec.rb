# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MiAuth web flow' do
  let(:user) { Fabricate(:user) }
  let(:session_id) { '11111111-2222-3333-4444-555555555555' }
  let(:callback) { 'flare://Callback/SignIn/Misskey' }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  context 'when authenticated' do
    before { sign_in user }

    it 'renders the approval page' do
      get "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }
      expect(response).to have_http_status(200)
    end

    it 'renders the completion page that navigates to the deeplink callback with session on approve' do
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }
      expect(response).to have_http_status(200)
      expect(response.body).to include("#{callback}?session=#{session_id}")
    end

    it 'allows the issued token to be claimed only once' do
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }

      post "/api/miauth/#{session_id}/check", as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body['ok']).to be true

      post "/api/miauth/#{session_id}/check", as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('ok' => false)
    end

    it 'ignores unsafe callback schemes on approve' do
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: 'javascript:alert(1)' }
      expect(response).to have_http_status(200)
      expect(response.body).to_not include('javascript:alert(1)')
    end

    it 'rejects session identifiers with insufficient entropy' do
      get '/miauth/12345678', params: { name: 'Flare', callback: callback }

      expect(response).to have_http_status(404)
    end
  end

  describe 'detailed user serialization for Flare' do
    let(:required_fields) do
      %i(id username createdAt isLocked isSilenced isSuspended fields followersCount followingCount notesCount pinnedNoteIds pinnedNotes publicReactions)
    end

    it 'includes every non-nullable field the Flare Misskey User model requires' do
      payload = MisskeyCompat::UserSerializer.serialize(user.account, detailed: true)
      expect(required_fields - payload.keys).to be_empty
    end
  end
end
