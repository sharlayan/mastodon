# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/mentions endpoint' do
  let(:user)     { Fabricate(:user) }
  let(:account)  { user.account }
  let(:token)    { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:followed) { Fabricate(:account, username: 'followed') }
  let(:stranger) { Fabricate(:account, username: 'stranger') }

  let!(:public_mention)  { mention_by(followed, visibility: :public) }
  let!(:direct_mention)  { mention_by(stranger, visibility: :direct) }
  let!(:limited_mention) { mention_by(followed, visibility: :limited, silent: true) }
  let!(:silent_public)   { mention_by(stranger, visibility: :public, silent: true) }

  before do
    Setting.misskey_compat_enabled = true
    account.follow!(followed)
  end

  after { Setting.misskey_compat_enabled = false }

  def mention_by(author, visibility:, silent: false)
    Fabricate(:status, account: author, visibility: visibility).tap do |status|
      Fabricate(:mention, status: status, account: account, silent: silent)
    end
  end

  def note_ids
    response.parsed_body.pluck(:id)
  end

  def encoded(*statuses)
    statuses.map { |status| MisskeyCompat::MiId.encode(status.id) }
  end

  it 'excludes silent mentions on public notes but keeps silent limited recipients' do
    post '/api/notes/mentions', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(note_ids).to match_array(encoded(public_mention, direct_mention, limited_mention))
    expect(note_ids).to_not include(*encoded(silent_public))
  end

  it 'returns only direct and limited notes for the specified visibility' do
    post '/api/notes/mentions', params: { i: token, visibility: 'specified' }, as: :json

    expect(response).to have_http_status(200)
    expect(note_ids).to match_array(encoded(direct_mention, limited_mention))
  end

  it 'filters by public visibility' do
    post '/api/notes/mentions', params: { i: token, visibility: 'public' }, as: :json

    expect(response).to have_http_status(200)
    expect(note_ids).to eq(encoded(public_mention))
  end

  it 'returns nothing for an unknown visibility' do
    post '/api/notes/mentions', params: { i: token, visibility: 'nonsense' }, as: :json

    expect(response).to have_http_status(200)
    expect(note_ids).to be_empty
  end

  it 'limits results to followed authors when following is true' do
    post '/api/notes/mentions', params: { i: token, following: true }, as: :json

    expect(response).to have_http_status(200)
    expect(note_ids).to match_array(encoded(public_mention, limited_mention))
  end
end
