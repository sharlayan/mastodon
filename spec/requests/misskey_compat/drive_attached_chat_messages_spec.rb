# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat Drive attached chat messages', :attachment_processing do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:other) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }
  let(:service) { Sharlayan::ChatService.new }
  let(:file) { DriveFile.create!(account: account, file: attachment_fixture('monochrome.png')) }
  let(:room) { service.create_conversation(account, type: :group, title: 'Attachments') }

  before do
    Setting.misskey_compat_enabled = true
    Setting.drive_enabled = true
    Setting.chat_enabled = true
    other.settings[:chat_policy] = 'everyone'
    other.save!
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
    Setting.chat_enabled = false
  end

  def mi_id(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  def attached(file_id, auth: token, **options)
    post '/api/drive/files/attached-chat-messages', params: { i: auth, fileId: file_id }.merge(options), as: :json
  end

  def create_with_file(drive_file, conversation: room)
    pointer = drive_file.build_pointer(account)
    pointer.save!
    service.create_message(account, conversation, text: 'attached', media_ids: [pointer.id])
  end

  it 'rejects ids and dates beyond the stored range as invalid parameters' do
    [
      [{ sinceId: '99999999999999999999' }, 'sinceId'],
      [{ untilId: '0zzzzzzzzzzzzzzz' }, 'untilId'],
      [{ sinceDate: 10**20 }, 'sinceDate'],
      [{ untilDate: -(10**20) }, 'untilDate'],
    ].each do |options, key|
      attached(mi_id(file), **options)

      expect(response).to have_http_status(400), options.inspect
      expect(response.parsed_body[:error]).to include(code: 'INVALID_PARAM', info: include(param: "#/properties/#{key}")), options.inspect
    end
  end

  it 'finds a Drive file attached using the actual Misskey chat create API, with detailed fields' do
    post '/api/chat/messages/create-to-user', params: { i: token, toUserId: mi_id(other.account), text: 'with file', fileId: mi_id(file) }, as: :json
    expect(response).to have_http_status(200)
    created = response.parsed_body

    attached(mi_id(file))

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to contain_exactly(include(id: created[:id], text: 'with file', fromUserId: mi_id(account), toUserId: mi_id(other.account), fileIds: [mi_id(file)], files: [include(id: mi_id(file))]))
  end

  it 'finds a file in any position of a message with multiple attachments without duplicating the message' do
    second = DriveFile.create!(account: account, file: attachment_fixture('text.png'))
    post '/api/chat/messages/create-to-user', params: { i: token, toUserId: mi_id(other.account), fileIds: [mi_id(file), mi_id(second)] }, as: :json
    expect(response).to have_http_status(200)
    message_id = response.parsed_body[:id]

    attached(mi_id(second))

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([message_id])
    expect(response.parsed_body.first[:fileIds]).to eq([mi_id(file), mi_id(second)])
  end

  it 'finds a legacy web-uploaded media attachment when native Drive is disabled' do
    Setting.drive_enabled = false
    media = Fabricate(:media_attachment, account: account, file: attachment_fixture('monochrome.png'))
    post '/api/chat/messages/create-to-user', params: { i: token, toUserId: mi_id(other.account), fileId: mi_id(media) }, as: :json
    expect(response).to have_http_status(200)
    message_id = response.parsed_body[:id]

    attached(mi_id(media))

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([message_id])
  end

  it 'returns the specified NO_SUCH_FILE error for another owner and a missing file' do
    foreign = DriveFile.create!(account: other.account, file: attachment_fixture('monochrome.png'))
    [mi_id(foreign), MisskeyCompat::MiId.encode(9_999_999_999)].each do |id|
      attached(id)
      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_FILE', id: '485ce26d-f5d2-4313-9783-e689d131eafb')
    end
  end

  it 'lets an administrator look up a foreign file but only returns messages in rooms they belong to' do
    admin = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator]))
    admin_token = Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read').token
    message = create_with_file(file)

    attached(mi_id(file), auth: admin_token)
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq([])

    room.memberships.create!(account: admin.account)
    attached(mi_id(file), auth: admin_token)
    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(message)])
  end

  it 'lets an administrator look up a Drive file when an unrelated user has a legacy media ID collision' do
    admin = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator]))
    admin_token = Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read').token
    file.update_columns(id: 8_765_432_101)
    unrelated = Fabricate(:media_attachment, account: other.account, file: attachment_fixture('monochrome.png'))
    unrelated.update_columns(id: file.id)

    attached(mi_id(file), auth: admin_token)

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq([])
  end

  it 'rejects a Drive and legacy media ID collision belonging to the file owner' do
    file.update_columns(id: 8_765_432_102)
    legacy = Fabricate(:media_attachment, account: account, file: attachment_fixture('monochrome.png'))
    legacy.update_columns(id: file.id)

    attached(mi_id(file))

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
  end

  it 'requires a functional account and an enabled chat service' do
    token
    user.update!(disabled: true)
    post '/api/chat/history', params: { i: token }, as: :json
    expect(response).to have_http_status(403)
    chat_error = response.parsed_body
    attached(mi_id(file))
    expect(response).to have_http_status(403)
    expect(response.parsed_body).to eq(chat_error)

    user.update!(disabled: false)
    Setting.chat_enabled = false
    attached(mi_id(file))
    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :code)).to eq('ENDPOINT_DISABLED')
  end

  it 'requires both Drive and Chat read permissions and a credential' do
    message = create_with_file(file)
    grant = MisskeyCompat::MiAuth.issue_token(user, name: 'Chat only', permissions: ['read:chat'])
    attached(mi_id(file), auth: grant.token)
    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')

    read_grant = MisskeyCompat::MiAuth.issue_token(user, name: 'Drive only', permissions: ['read:drive'])
    attached(mi_id(file), auth: read_grant.token)
    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')

    both_grant = MisskeyCompat::MiAuth.issue_token(user, name: 'Drive and Chat', permissions: ['read:drive', 'read:chat'])
    attached(mi_id(file), auth: both_grant.token)
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to contain_exactly(include(id: mi_id(message), text: 'attached'))

    post '/api/drive/files/attached-chat-messages', params: { fileId: mi_id(file) }, as: :json
    expect(response).to have_http_status(401)
  end

  it 'paginates visible messages by ID and date, and uses the nearest newer results for since cursors' do
    messages = Array.new(4) { create_with_file(file) }
    base = Time.zone.local(2026, 1, 1)
    messages.each_with_index { |message, index| message.update_column(:created_at, base + index.hours) }

    attached(mi_id(file), limit: 2)
    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq(messages.last(2).reverse.map { |message| mi_id(message) })
    attached(mi_id(file), untilId: mi_id(messages[2]))
    expect(response.parsed_body.pluck(:id)).to eq(messages.first(2).reverse.map { |message| mi_id(message) })
    attached(mi_id(file), sinceId: mi_id(messages.first), limit: 2)
    expect(response.parsed_body.pluck(:id)).to eq(messages[1..2].map { |message| mi_id(message) })
    attached(mi_id(file), sinceDate: (base + 1.hour).to_i * 1000, limit: 2)
    expect(response.parsed_body.pluck(:id)).to eq(messages[2..3].map { |message| mi_id(message) })
    attached(mi_id(file), untilDate: (base + 2.hours).to_i * 1000)
    expect(response.parsed_body.pluck(:id)).to eq(messages.first(2).reverse.map { |message| mi_id(message) })
  end

  it 'excludes messages from inaccessible conversations, hidden own messages and deleted tombstones before limiting' do
    visible = create_with_file(file)
    hidden = create_with_file(file)
    hidden.update_column(:hidden_at, Time.current)
    deleted = create_with_file(file)
    deleted.update_column(:deleted_at, Time.current)
    inaccessible = create_with_file(file, conversation: service.create_conversation(account, type: :group, title: 'Left'))
    inaccessible.chat_conversation.memberships.where(account: account).delete_all

    attached(mi_id(file), limit: 1)

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(visible)])
  end

  it 'defaults to ten messages and does not alter the chat read marker' do
    messages = Array.new(11) { create_with_file(file) }
    membership = room.memberships.find_by!(account: account)
    membership.update!(last_read_message: nil)

    attached(mi_id(file))

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq(messages.last(10).reverse.map { |message| mi_id(message) })
    expect(membership.reload.last_read_message_id).to be_nil
  end

  it 'validates required file IDs and the pagination limit' do
    post '/api/drive/files/attached-chat-messages', params: { i: token }, as: :json
    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')

    [0, 101, '10'].each do |limit|
      attached(mi_id(file), limit: limit)
      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end
  end
end
