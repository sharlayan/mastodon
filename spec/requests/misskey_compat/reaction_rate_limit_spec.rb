# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat reaction rate limit' do
  let(:user)   { Fabricate(:user) }
  let(:token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }
  let(:status) { Fabricate(:status) }

  before do
    Setting.misskey_compat_enabled = true
    Setting.reactions_enabled = true
  end

  after { Setting.misskey_compat_enabled = false }

  it 'shares the authenticated reaction budget with the native endpoint' do
    limiter = RateLimiter.new(user.account, family: :status_reactions)
    RateLimiter::FAMILIES[:status_reactions][:limit].times { limiter.record! }

    expect do
      post '/api/notes/reactions/create',
           params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id), reaction: '👍' },
           as: :json
    end.to_not change(StatusReaction, :count)

    expect(response).to have_http_status(429)
    expect(response.parsed_body.dig('error', 'code')).to eq('RATE_LIMIT_EXCEEDED')
  end
end
