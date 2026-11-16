# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Limited replies API' do
  include_context 'with API authentication'

  let(:scopes) { 'read:statuses write:statuses' }
  let(:author) { Fabricate(:account) }
  let(:recipient) { Fabricate(:account) }
  let(:outsider) { Fabricate(:account) }
  let(:parent) { Fabricate(:status, account: author, visibility: :limited, limited_scope: :circle) }
  let(:params) { { status: 'A reply', in_reply_to_id: parent.id, visibility: 'private', limited_scope: 'reply' } }

  before do
    parent.mentions.create!(account: user.account, silent: true)
    parent.mentions.create!(account: recipient, silent: true)
  end

  it 'creates and redrafts a reply with the original recipient snapshot after the parent audience changes' do
    post '/api/v1/statuses', headers: headers, params: params
    expect(response).to have_http_status(200), response.body
    expect(response.parsed_body).to include(visibility: 'private', limited_scope: 'reply')
    status_id = response.parsed_body.fetch(:id)
    delete "/api/v1/statuses/#{status_id}", headers: headers
    expect(response).to have_http_status(200), response.body
    audience = response.parsed_body.fetch(:limited_reply_account_ids)
    expect(audience).to contain_exactly(author.id.to_s, recipient.id.to_s)
    parent.mentions.create!(account: outsider, silent: true)

    post '/api/v1/statuses', headers: headers, params: params.merge(limited_reply_account_ids: audience)
    expect(response).to have_http_status(200), response.body
    expect(Status.find(response.parsed_body.fetch(:id)).mentions.pluck(:account_id)).to contain_exactly(author.id, recipient.id)
  end

  it 'returns 422 for invalid targets and recipient expansion without creating a status' do
    parent.update!(limited_scope: nil)
    get "/api/v1/statuses/#{parent.id}", headers: headers
    expect(response.parsed_body).to include(limited_scope: 'none')

    post '/api/v1/statuses', headers: headers, params: params.merge(in_reply_to_id: nil)
    expect(response).to have_http_status(422)
    post '/api/v1/statuses', headers: headers, params: params.merge(status: "@#{outsider.acct} outside")
    expect(response).to have_http_status(422)
    expect(user.account.statuses).to be_empty
  end

  it 'freezes a newly saved reply draft and preserves its audience when resaved without recipient IDs' do
    post '/api/v1/status_drafts', headers: headers, params: params
    expect(response).to have_http_status(200), response.body
    draft_id = response.parsed_body.fetch(:id)
    snapshot = response.parsed_body.fetch(:params)
    expect(snapshot).to include(limited_scope: 'reply', visibility: 'private')
    expect(snapshot.fetch(:limited_reply_account_ids)).to contain_exactly(author.id.to_s, recipient.id.to_s, user.account.id.to_s)
    parent.mentions.create!(account: outsider, silent: true)

    put "/api/v1/status_drafts/#{draft_id}", headers: headers, params: params.merge(status: 'A resaved reply')
    expect(response).to have_http_status(200), response.body
    expect(response.parsed_body.fetch(:params).fetch(:limited_reply_account_ids)).to eq(snapshot.fetch(:limited_reply_account_ids))
    put "/api/v1/status_drafts/#{draft_id}", headers: headers, params: { status: 'A partial update' }
    expect(response).to have_http_status(200), response.body
    expect(response.parsed_body.fetch(:params).fetch(:limited_reply_account_ids)).to eq(snapshot.fetch(:limited_reply_account_ids))
    post '/api/v1/statuses', headers: headers, params: response.parsed_body.fetch(:params), as: :json
    expect(response).to have_http_status(200), response.body
    expect(Status.find(response.parsed_body.fetch(:id)).mentions.pluck(:account_id)).to contain_exactly(author.id, recipient.id)
  end

  it 'saves a reply draft after its scope is left or its parent becomes unavailable' do
    draft_ids = Array.new(2) do
      post '/api/v1/status_drafts', headers: headers, params: params
      response.parsed_body.fetch(:id)
    end

    put "/api/v1/status_drafts/#{draft_ids.first}", headers: headers, params: { status: 'Now public', in_reply_to_id: parent.id, visibility: 'public' }
    expect(response).to have_http_status(200), response.body
    expect(response.parsed_body.fetch(:params)).to include(visibility: 'public', in_reply_to_id: parent.id.to_s).and(not_include(:limited_scope, :limited_reply_account_ids))
    put "/api/v1/status_drafts/#{draft_ids.first}", headers: headers, params: params
    expect(response).to have_http_status(200), response.body

    user.account.block!(author)
    put "/api/v1/status_drafts/#{draft_ids.first}", headers: headers, params: { status: 'A partial update' }
    expect(response).to have_http_status(200), response.body
    expect(response.parsed_body.fetch(:params)).to include(visibility: 'direct').and(not_include(:limited_scope, :limited_reply_account_ids, :in_reply_to_id))

    parent.destroy!
    put "/api/v1/status_drafts/#{draft_ids.last}", headers: headers, params: params
    expect(response).to have_http_status(200), response.body
    expect(response.parsed_body.fetch(:params)).to include(status: 'A reply', visibility: 'direct').and(not_include(:limited_scope, :limited_reply_account_ids, :in_reply_to_id))
  end

  it 'rejects a reply draft whose parent is not accessible or limited' do
    private_parent = Fabricate(:status, visibility: :limited)
    public_parent = Fabricate(:status)
    [private_parent, public_parent].each do |thread|
      post '/api/v1/status_drafts', headers: headers, params: params.merge(in_reply_to_id: thread.id)
      expect(response).to have_http_status(thread == private_parent ? 403 : 422)
    end
    expect(user.account.status_drafts).to be_empty
  end
end
