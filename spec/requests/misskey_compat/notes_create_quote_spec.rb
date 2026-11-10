# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/create quote checks' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }
  let(:author)  { Fabricate(:account, username: 'author') }
  let(:automatic_public) { InteractionPolicy::POLICY_FLAGS[:public] << 16 }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def quote(status, **extra)
    post '/api/notes/create', params: { i: token, text: 'quoting', renoteId: MisskeyCompat::MiId.encode(status.id), **extra }, as: :json
  end

  def error_code
    response.parsed_body.dig(:error, :code)
  end

  def error_id
    response.parsed_body.dig(:error, :id)
  end

  def created_status
    Status.find(MisskeyCompat::MiId.decode(response.parsed_body.dig(:createdNote, :id)))
  end

  it 'quotes a status whose policy allows it and keeps a manually approved remote quote pending like the REST API' do
    quoted = Fabricate(:status, account: author, quote_approval_policy: automatic_public)

    quote(quoted)

    expect(response).to have_http_status(200)
    expect(created_status.quote).to have_attributes(quoted_status: quoted, state: 'accepted')

    remote = Fabricate(:account, username: 'remote', domain: 'remote.example')
    remote_quoted = Fabricate(:status, account: remote, quote_approval_policy: InteractionPolicy::POLICY_FLAGS[:public])

    quote(remote_quoted)

    expect(response).to have_http_status(200)
    expect(created_status.quote).to have_attributes(quoted_status: remote_quoted, state: 'pending')
  end

  it 'rejects a status whose quote policy denies the requester and quoting a pure boost' do
    quoted = Fabricate(:status, account: author)

    quote(quoted)

    expect(response).to have_http_status(400)
    expect(error_code).to eq('CANNOT_RENOTE_DUE_TO_VISIBILITY')
    expect(error_id).to eq('be9529e9-fe72-4de0-ae43-0b363c4938af')
    expect(account.statuses).to be_empty
    expect(Quote.where(quoted_status: quoted)).to be_empty

    original = Fabricate(:status, account: author, quote_approval_policy: automatic_public)
    boost = Fabricate(:status, account: Fabricate(:account), reblog: original)

    quote(boost)

    expect(response).to have_http_status(400)
    expect(error_code).to eq('CANNOT_RENOTE_TO_A_PURE_RENOTE')
    expect(error_id).to eq('fd4cc33e-2a37-48dd-99cc-9b806eb2031a')
    expect(account.statuses).to be_empty
  end

  it 'rejects a status by an author the requester blocks' do
    quoted = Fabricate(:status, account: author, quote_approval_policy: automatic_public)
    account.block!(author)

    quote(quoted)

    expect(response).to have_http_status(400)
    expect(error_code).to eq('CANNOT_RENOTE_DUE_TO_VISIBILITY')
    expect(account.statuses).to be_empty
  end

  it 'returns YOU_HAVE_BEEN_BLOCKED for a quote or renote of an author who blocks the requester' do
    quoted = Fabricate(:status, account: author, quote_approval_policy: automatic_public)
    original = Fabricate(:status, account: author)
    author.block!(account)

    quote(quoted)

    expect(response).to have_http_status(400)
    expect(error_code).to eq('YOU_HAVE_BEEN_BLOCKED')
    expect(error_id).to eq('b390d7e1-8a5e-46ed-b625-06271cafd3d3')

    post '/api/notes/create', params: { i: token, renoteId: MisskeyCompat::MiId.encode(original.id) }, as: :json

    expect(response).to have_http_status(400)
    expect(error_code).to eq('YOU_HAVE_BEEN_BLOCKED')
    expect(account.statuses).to be_empty
  end

  it 'returns NO_SUCH_RENOTE_TARGET for unknown quote and renote targets and quote targets the requester cannot see' do
    post '/api/notes/create', params: { i: token, text: 'quoting', renoteId: MisskeyCompat::MiId.encode(999_999_999) }, as: :json

    expect(response).to have_http_status(404)
    expect(error_code).to eq('NO_SUCH_RENOTE_TARGET')
    expect(error_id).to eq('b5c90186-4ab0-49c8-9bba-a1f76c282ba4')

    quote(Fabricate(:status, account: author, visibility: :private, quote_approval_policy: automatic_public))

    expect(response).to have_http_status(404)
    expect(error_code).to eq('NO_SUCH_RENOTE_TARGET')

    post '/api/notes/create', params: { i: token, renoteId: MisskeyCompat::MiId.encode(999_999_999) }, as: :json

    expect(response).to have_http_status(404)
    expect(error_code).to eq('NO_SUCH_RENOTE_TARGET')
  end

  it 'still renotes a public status without a quote policy' do
    original = Fabricate(:status, account: author)

    post '/api/notes/create', params: { i: token, renoteId: MisskeyCompat::MiId.encode(original.id) }, as: :json

    expect(response).to have_http_status(200)
    expect(account.statuses.last.reblog).to eq(original)
  end
end
