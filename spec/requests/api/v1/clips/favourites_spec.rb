# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Clip Favourites' do
  include_context 'with API authentication', oauth_scopes: 'read:lists write:lists'

  let(:other) { Fabricate(:account) }

  before { Setting.clips_enabled = true }

  describe 'POST /api/v1/clips/:clip_id/favourite' do
    subject { post "/api/v1/clips/#{clip.id}/favourite", headers: headers }

    context 'with a public clip owned by someone else' do
      let(:clip) { Fabricate(:clip, account: other, public: true, title: 'public') }

      it 'creates a favourite and reports favourited' do
        expect { subject }.to change(ClipFavourite, :count).by(1)
        expect(response).to have_http_status(200)
        expect(response.parsed_body[:favourited]).to be(true)
        expect(user.account.favourite_clips).to include(clip)
      end

      it 'is idempotent when called twice' do
        post "/api/v1/clips/#{clip.id}/favourite", headers: headers
        expect { subject }.to_not change(ClipFavourite, :count)
        expect(response).to have_http_status(200)
      end
    end

    context 'with a private clip owned by someone else' do
      let(:clip) { Fabricate(:clip, account: other, public: false, title: 'secret') }

      it 'returns 404 and does not create a favourite' do
        expect { subject }.to_not change(ClipFavourite, :count)
        expect(response).to have_http_status(404)
      end
    end

    context 'with the feature disabled' do
      let(:clip) { Fabricate(:clip, account: other, public: true) }

      before { Setting.clips_enabled = false }

      it 'returns 404' do
        subject
        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'POST /api/v1/clips/:clip_id/unfavourite' do
    subject { post "/api/v1/clips/#{clip.id}/unfavourite", headers: headers }

    context 'with a public clip currently favourited' do
      let(:clip) { Fabricate(:clip, account: other, public: true) }

      before { user.account.clip_favourites.create!(clip: clip) }

      it 'removes the favourite' do
        expect { subject }.to change(ClipFavourite, :count).by(-1)
        expect(response).to have_http_status(200)
        expect(user.account.favourite_clips).to_not include(clip)
      end
    end

    context 'when a favourited clip has since been made private by its owner' do
      let(:clip) { Fabricate(:clip, account: other, public: true) }

      before do
        user.account.clip_favourites.create!(clip: clip)
        clip.update!(public: false)
      end

      it 'still allows removing the orphaned favourite' do
        expect { subject }.to change(ClipFavourite, :count).by(-1)
        expect(response).to have_http_status(200)
      end
    end

    context 'with a private clip the user never favourited' do
      let(:clip) { Fabricate(:clip, account: other, public: false, title: 'secret') }

      it 'returns 404 without leaking the clip' do
        subject
        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'GET /api/v1/clips/favourites' do
    subject { get '/api/v1/clips/favourites', headers: headers }

    let(:public_clip) { Fabricate(:clip, account: other, public: true, title: 'kept') }
    let(:hidden_clip) { Fabricate(:clip, account: other, public: true, title: 'hidden') }

    before do
      user.account.clip_favourites.create!(clip: public_clip)
      user.account.clip_favourites.create!(clip: hidden_clip)
      hidden_clip.update!(public: false)
    end

    it 'returns only favourited clips that remain visible' do
      subject

      expect(response).to have_http_status(200)
      ids = response.parsed_body.pluck(:id)
      expect(ids).to include(public_clip.id.to_s)
      expect(ids).to_not include(hidden_clip.id.to_s)
    end

    context 'without a user token' do
      let(:token) { Fabricate(:accessible_access_token, resource_owner_id: nil, scopes: 'read:lists') }

      it 'requires a user' do
        subject
        expect(response).to have_http_status(422)
      end
    end
  end
end
