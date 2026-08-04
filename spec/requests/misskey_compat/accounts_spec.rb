# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat account endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:target)      { Fabricate(:account) }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/users/update-memo' do
    it 'requires authentication' do
      post '/api/users/update-memo', params: { userId: target.id, memo: 'private note' }, as: :json

      expect(response).to have_http_status(401)
      expect(response.parsed_body.dig(:error, :code)).to eq('CREDENTIAL_REQUIRED')
    end

    it 'rejects a read-only token without changing data' do
      post '/api/users/update-memo', params: { i: read_token, userId: target.id, memo: 'private note' }, as: :json

      expect(response).to have_http_status(403)
      expect(account.account_notes).to be_empty
    end

    it 'creates, updates, and clears a memo using a MiId userId' do
      encoded_id = MisskeyCompat::MiId.encode(target.id)

      post '/api/users/update-memo', params: { i: write_token, userId: encoded_id, memo: 'first' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.account_notes.find_by(target_account: target)&.comment).to eq('first')

      post '/api/users/update-memo', params: { i: write_token, userId: encoded_id, memo: 'second' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.account_notes.find_by(target_account: target)&.comment).to eq('second')

      post '/api/users/update-memo', params: { i: write_token, userId: encoded_id, memo: '' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.account_notes.find_by(target_account: target)).to be_nil
    end

    it 'returns NO_SUCH_USER for an unknown account' do
      post '/api/users/update-memo', params: { i: write_token, userId: MisskeyCompat::MiId.encode(-1), memo: 'private note' }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER')
    end
  end

  describe 'POST /api/users/search' do
    it 'requires a read-capable token' do
      post '/api/users/search', params: { i: write_token, query: target.username }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    end

    it 'returns an empty result for a blank query' do
      post '/api/users/search', params: { i: read_token, query: '   ' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end
  end
end
