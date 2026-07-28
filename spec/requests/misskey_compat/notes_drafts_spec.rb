# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/drafts endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  def rpc_post(endpoint, params = {})
    post "/api/#{endpoint}", params: params.merge(i: token), as: :json
  end

  it 'advertises all server draft endpoints for Misskey clients' do
    expect(Api::MisskeyCompat::MetaController.compat_endpoint_names).to include(
      'notes/drafts/list',
      'notes/drafts/count',
      'notes/drafts/create',
      'notes/drafts/update',
      'notes/drafts/delete'
    )
  end

  it 'creates and serializes a draft with compose fields and media', :aggregate_failures do
    media = Fabricate(:media_attachment, account: account)

    rpc_post 'notes/drafts/create',
             text: 'Misskey draft',
             cw: 'CW',
             visibility: 'followers',
             localOnly: true,
             fileIds: [MisskeyCompat::MiId.encode(media.id)],
             poll: { choices: %w(One Two), multiple: true, expiredAfter: 3600 }

    expect(response).to have_http_status(200)
    created = response.parsed_body[:createdDraft]
    expect(created).to include(
      text: 'Misskey draft',
      cw: 'CW',
      visibility: 'followers',
      localOnly: true,
      isActuallyScheduled: false
    )
    expect(created[:poll]).to include(choices: %w(One Two), multiple: true, expiredAfter: 3600)
    expect(created[:fileIds]).to eq([MisskeyCompat::MiId.encode(media.id)])
    expect(media.reload.status_draft_id).to eq(StatusDraft.last.id)
  end

  it 'accepts a Drive file ID and returns the same ID' do
    Setting.drive_enabled = true
    drive_file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

    rpc_post 'notes/drafts/create', text: 'Drive draft', fileIds: [MisskeyCompat::MiId.encode(drive_file.id)]

    expect(response).to have_http_status(200)
    expect(response.parsed_body.dig(:createdDraft, :fileIds)).to eq([MisskeyCompat::MiId.encode(drive_file.id)])
    expect(StatusDraft.last.media_attachments.first.drive_file_id).to eq(drive_file.id)
  ensure
    Setting.drive_enabled = false
  end

  it 'lists, counts, updates, and deletes drafts', :aggregate_failures do
    media = Fabricate(:media_attachment, account: account)
    rpc_post 'notes/drafts/create',
             text: 'Initial',
             cw: 'Keep me',
             visibility: 'public',
             fileIds: [MisskeyCompat::MiId.encode(media.id)]
    draft_id = response.parsed_body.dig(:createdDraft, :id)

    rpc_post 'notes/drafts/count'
    expect(response.parsed_body).to eq(1)

    rpc_post 'notes/drafts/list', scheduled: false
    expect(response.parsed_body.pluck(:id)).to eq([draft_id])

    rpc_post 'notes/drafts/list', scheduled: true
    expect(response.parsed_body).to eq([])

    rpc_post 'notes/drafts/update', draftId: draft_id, text: 'Updated', visibility: 'home'
    expect(response).to have_http_status(200)
    expect(response.parsed_body.dig(:updatedDraft, :text)).to eq('Updated')
    expect(response.parsed_body.dig(:updatedDraft, :visibility)).to eq('home')
    expect(response.parsed_body.dig(:updatedDraft, :cw)).to eq('Keep me')
    expect(response.parsed_body.dig(:updatedDraft, :fileIds)).to eq([MisskeyCompat::MiId.encode(media.id)])

    rpc_post 'notes/drafts/delete', draftId: draft_id
    expect(response).to have_http_status(204)
    expect(account.status_drafts).to be_empty
  end

  it 'caps draft list responses at the server limit' do
    (StatusDraft::LIST_LIMIT + 1).times { Fabricate(:status_draft, account: account) }

    rpc_post 'notes/drafts/list', limit: 100

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(StatusDraft::LIST_LIMIT)
  end

  it 'isolates drafts and attached media by account', :aggregate_failures do
    foreign_draft = Fabricate(:status_draft)
    foreign_media = Fabricate(:media_attachment)

    rpc_post 'notes/drafts/update', draftId: MisskeyCompat::MiId.encode(foreign_draft.id), text: 'Stolen'
    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_NOTE_DRAFT')

    rpc_post 'notes/drafts/create', text: 'Invalid media', fileIds: [MisskeyCompat::MiId.encode(foreign_media.id)]
    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FILE')
    expect(foreign_draft.reload.data['status']).to eq('Saved draft')
  end

  it 'does not accept an invisible reply or renote reference' do
    private_status = Fabricate(:status, visibility: :direct)

    rpc_post 'notes/drafts/create', text: 'Hidden reply', replyId: MisskeyCompat::MiId.encode(private_status.id)

    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_REPLY_TARGET')
    expect(account.status_drafts).to be_empty
  end

  it 'rejects scheduled drafts instead of pretending they will publish' do
    rpc_post 'notes/drafts/create', text: 'Scheduled', scheduledAt: 1.hour.from_now.to_i * 1000, isActuallyScheduled: true

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    expect(account.status_drafts).to be_empty
  end

  it 'enforces read and write OAuth scopes' do
    read_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token
    write_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token

    post '/api/notes/drafts/create', params: { i: read_token, text: 'Denied' }, as: :json
    expect(response).to have_http_status(403)

    post '/api/notes/drafts/list', params: { i: write_token }, as: :json
    expect(response).to have_http_status(403)
  end

  it 'enforces fine-grained MiAuth account permissions' do
    access_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write')
    MisskeyAccessGrant.create!(access_token: access_token, permissions: ['read:account'])

    post '/api/notes/drafts/list', params: { i: access_token.token }, as: :json
    expect(response).to have_http_status(200)

    post '/api/notes/drafts/create', params: { i: access_token.token, text: 'Denied' }, as: :json
    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
  end
end
