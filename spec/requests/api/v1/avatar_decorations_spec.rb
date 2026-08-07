# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avatar Decorations' do
  include_context 'with API authentication'

  before do
    Setting.avatar_decorations_enabled = true

    stub_request(:get, %r{\Ahttps://(example\.com|remote\.example)/})
      .to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').read, headers: { 'Content-Type' => 'image/png' })
  end

  describe 'GET /api/v1/avatar_decorations' do
    before do
      Fabricate(:avatar_decoration, approved: true, name: 'sparkle')
      Fabricate(:avatar_decoration, approved: false, name: 'hidden')
      Fabricate(:avatar_decoration, approved: true, host: 'remote.example', image_remote_url: 'https://remote.example/d.png', remote_id: 'r1', image: nil)
    end

    it 'returns only approved local decorations' do
      get api_v1_avatar_decorations_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.content_type).to start_with('application/json')

      names = response.parsed_body.pluck(:name)
      expect(names).to include('sparkle')
      expect(names).to_not include('hidden')
    end

    context 'when feature is disabled' do
      before { Setting.avatar_decorations_enabled = false }

      it 'returns 404' do
        get api_v1_avatar_decorations_path, headers: headers

        expect(response).to have_http_status(404)
      end
    end

    context 'when only remote decorations may be viewed' do
      before { Setting.avatar_decorations_local_only_view = true }

      it 'returns 404' do
        get api_v1_avatar_decorations_path, headers: headers

        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'POST /api/v1/avatar_decoration_mutes' do
    let(:scopes) { 'write:mutes' }
    let(:target_account) { Fabricate(:account) }

    it 'returns http forbidden without the write:mutes scope' do
      post api_v1_avatar_decoration_mutes_path,
           params: { account_id: target_account.id },
           headers: { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token}" }

      expect(response).to have_http_status(403)
    end

    context 'with account_id' do
      it 'creates a mute' do
        post api_v1_avatar_decoration_mutes_path,
             params: { account_id: target_account.id },
             headers: headers

        expect(response).to have_http_status(200)
        expect(response.parsed_body[:target_account_id]).to eq(target_account.id.to_s)
        expect(user.account.avatar_decoration_mutes.where(target_account: target_account)).to exist
      end

      it 'is idempotent' do
        2.times do
          post api_v1_avatar_decoration_mutes_path,
               params: { account_id: target_account.id },
               headers: headers
        end

        expect(response).to have_http_status(200)
        expect(user.account.avatar_decoration_mutes.where(target_account: target_account).count).to eq(1)
      end
    end

    context 'with domain' do
      it 'creates a domain mute' do
        post api_v1_avatar_decoration_mutes_path,
             params: { domain: 'example.com' },
             headers: headers

        expect(response).to have_http_status(200)
        expect(response.parsed_body[:target_domain]).to eq('example.com')
      end
    end

    context 'without account_id or domain' do
      it 'returns 422' do
        post api_v1_avatar_decoration_mutes_path,
             params: {},
             headers: headers

        expect(response).to have_http_status(422)
      end
    end
  end

  describe 'DELETE /api/v1/avatar_decoration_mutes/:id' do
    let(:scopes) { 'write:mutes' }
    let(:target_account) { Fabricate(:account) }

    it 'destroys the mute' do
      mute = user.account.avatar_decoration_mutes.create!(target_account: target_account)

      delete api_v1_avatar_decoration_mute_path(mute.id), headers: headers

      expect(response).to have_http_status(200)
      expect(user.account.avatar_decoration_mutes.where(id: mute.id)).to_not exist
    end
  end
end
