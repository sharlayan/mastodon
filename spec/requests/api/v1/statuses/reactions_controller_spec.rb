# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reactions', :inline_jobs do
  let(:user)    { Fabricate(:user) }
  let(:scopes)  { 'write:favourites' }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  describe 'POST /api/v1/statuses/:status_id/react/:id' do
    subject do
      post "/api/v1/statuses/#{status.id}/react/#{CGI.escape('👍')}", headers: headers
    end

    let(:status) { Fabricate(:status) }

    it_behaves_like 'forbidden for wrong scope', 'read read:favourites'

    context 'with public status' do
      it 'reacts to the status successfully and includes updated json', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type)
          .to start_with('application/json')
        expect(user.account.reacted?(status, '👍')).to be true

        expect(response.parsed_body).to match(
          a_hash_including(id: status.id.to_s, reactions: [a_hash_including(name: '👍', count: 1, me: true)])
        )
      end

      it 'rate limits repeated authenticated reaction changes' do
        allow(redis).to receive(:time).and_return([1_786_190_000, 0])

        limiter = RateLimiter.new(user.account, family: :status_reactions)
        RateLimiter::FAMILIES[:status_reactions][:limit].times { limiter.record! }

        expect { subject }.to_not change(StatusReaction, :count)

        expect(response).to have_http_status(429)
        expect(response.headers['Cache-Control']).to eq('private, no-store')
        expect(response.headers['Retry-After'].to_i).to be_positive
      end
    end

    context 'with private status of not-followed account' do
      let(:status) { Fabricate(:status, visibility: :private) }

      it 'returns http not found' do
        subject

        expect(response).to have_http_status(404)
        expect(response.content_type)
          .to start_with('application/json')
      end
    end

    context 'with private status of followed account' do
      let(:status) { Fabricate(:status, visibility: :private) }

      before do
        user.account.follow!(status.account)
      end

      it 'reacts to the status successfully', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type)
          .to start_with('application/json')
        expect(user.account.reacted?(status, '👍')).to be true
      end
    end

    context 'without an authorization header' do
      let(:headers) { {} }

      it 'returns http unauthorized' do
        subject

        expect(response).to have_http_status(401)
        expect(response.content_type)
          .to start_with('application/json')
      end
    end
  end

  describe 'POST /api/v1/statuses/:status_id/unreact/:id' do
    subject do
      post "/api/v1/statuses/#{status.id}/unreact/#{CGI.escape('👍')}", headers: headers
    end

    let(:status) { Fabricate(:status) }

    it_behaves_like 'forbidden for wrong scope', 'read read:favourites'

    context 'with public status' do
      before do
        ReactService.new.call(user.account, status, '👍')
      end

      it 'unreacts the status successfully and includes updated json', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type)
          .to start_with('application/json')

        expect(user.account.reacted?(status, '👍')).to be false

        expect(response.parsed_body).to match(
          a_hash_including(id: status.id.to_s, reactions_count: 0, reactions: [])
        )
      end
    end

    context 'when the requesting user was blocked by the status author' do
      before do
        ReactService.new.call(user.account, status, '👍')
        status.account.block!(user.account)
      end

      it 'unreacts the status successfully and includes updated json', :aggregate_failures do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type)
          .to start_with('application/json')

        expect(user.account.reacted?(status, '👍')).to be false

        expect(response.parsed_body).to match(
          a_hash_including(id: status.id.to_s, reactions_count: 0, reactions: [])
        )
      end
    end

    context 'when status is not reacted to' do
      it 'returns http success' do
        subject

        expect(response).to have_http_status(200)
        expect(response.content_type)
          .to start_with('application/json')
      end
    end

    context 'with private status that was not reacted to' do
      let(:status) { Fabricate(:status, visibility: :private) }

      it 'returns http not found' do
        subject

        expect(response).to have_http_status(404)
        expect(response.content_type)
          .to start_with('application/json')
      end
    end
  end
end
