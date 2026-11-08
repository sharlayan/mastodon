# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat chat endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:other) { Fabricate(:user) }
  let(:outsider) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:service) { Sharlayan::ChatService.new }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.misskey_compat_enabled = true
    Setting.chat_enabled = true
    Setting.chat_soft_delete_enabled = false
    other.settings[:chat_policy] = 'everyone'
    other.settings[:chat_allow_group_invites] = true
    other.save!
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.chat_enabled = false
    Setting.chat_soft_delete_enabled = false
  end

  def request_chat(endpoint, params = {}, as_user: nil, **values)
    access_token = as_user ? Fabricate(:accessible_access_token, resource_owner_id: as_user.id, scopes: 'read write') : token
    post "/api/chat/#{endpoint}", params: params.merge(values).merge(i: access_token.token), as: :json
  end

  def mi_id(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  def counted_queries(pattern, &block)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if !payload[:cached] && payload[:sql].match?(pattern) }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  def direct_conversation
    service.create_conversation(account, type: :direct, account_ids: [other.account.id])
  end

  def group_conversation
    service.create_conversation(account, type: :group, title: 'Room')
  end

  it 'requires authentication instead of returning an empty successful response' do
    post '/api/chat/history', as: :json

    expect(response).to have_http_status(401)
    expect(response.parsed_body.dig(:error, :code)).to eq('CREDENTIAL_REQUIRED')
  end

  it 'requires both chat and compatibility feature gates' do
    Setting.chat_enabled = false
    request_chat('history')
    expect(response).to have_http_status(404)

    Setting.chat_enabled = true
    Setting.misskey_compat_enabled = false
    request_chat('history')
    expect(response).to have_http_status(404)
  end

  it 'prevents a read-only token from creating a message' do
    token.update!(scopes: 'read')
    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

    expect(response).to have_http_status(403)
    expect(ChatMessage.count).to be_zero
  end

  it 'prevents a write-only token from reading history' do
    token.update!(scopes: 'write')
    request_chat('history')

    expect(response).to have_http_status(403)
  end

  it 'enforces the write limit for a bypass role when server bypass is disabled' do
    user.role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:bypass_rate_limit])
    Setting.rate_limit_bypass_enabled = false
    limiter = instance_double(RateLimiter)
    allow(RateLimiter).to receive(:new).with(account, family: :chat_writes).and_return(limiter)
    allow(limiter).to receive(:record!).and_raise(Mastodon::RateLimitExceededError)

    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

    expect(response).to have_http_status(429)
    expect(ChatMessage.count).to be_zero
  end

  it 'lets a bypass role skip the write limit when server bypass is enabled' do
    user.role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:bypass_rate_limit])
    Setting.rate_limit_bypass_enabled = true
    allow(RateLimiter).to receive(:new).and_call_original

    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

    expect(response).to have_http_status(200)
    expect(RateLimiter).to_not have_received(:new).with(account, family: :chat_writes)
  ensure
    Setting.rate_limit_bypass_enabled = false
  end

  it 'creates direct messages with decoded IDs and returns the stored message' do
    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(text: 'hello', fromUserId: mi_id(account), toUserId: mi_id(other.account))
    expect(ChatMessage.last.text).to eq('hello')
    expect(response.parsed_body[:id]).to eq(mi_id(ChatMessage.last))
    expect(ChatMessage.last.uri).to be_present
  end

  it 'rejects self recipients without creating a conversation' do
    request_chat('messages/create-to-user', toUserId: mi_id(account), text: 'hello')

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('RECIPIENT_IS_YOURSELF')
    expect(ChatConversation.count).to be_zero
  end

  it 'validates message content before creating a direct conversation' do
    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: '')

    expect(response).to have_http_status(400)
    expect(ChatConversation.count).to be_zero
  end

  it 'keeps the local text limit at 4096 Unicode codepoints' do
    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: '🍒' * 4096)
    expect(response).to have_http_status(200)

    request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: '🍒' * 4097)
    expect(response).to have_http_status(400)
    expect(ChatMessage.count).to eq(1)
  end

  it 'reads and paginates the direct timeline while advancing its read marker' do
    conversation = direct_conversation
    first = service.create_message(other.account, conversation, text: 'first')
    second = service.create_message(other.account, conversation, text: 'second')

    request_chat('messages/user-timeline', userId: mi_id(other.account), limit: 1)
    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(second)])
    expect(conversation.memberships.find_by!(account: account).last_read_message_id).to eq(second.id)

    request_chat('messages/user-timeline', userId: mi_id(other.account), untilId: mi_id(second))
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(first)])
  end

  it 'returns no direct timeline for a new pair without creating one' do
    request_chat('messages/user-timeline', userId: mi_id(other.account))

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq([])
    expect(ChatConversation.count).to be_zero
  end

  it 'returns direct and room histories separately with read state' do
    direct = direct_conversation
    message = service.create_message(other.account, direct, text: 'unread')
    room = group_conversation
    group_message = service.create_message(account, room, text: 'room')

    request_chat('history')
    expect(response.parsed_body).to contain_exactly(include(id: mi_id(message), isRead: false))

    request_chat('history', room: true)
    expect(response.parsed_body).to contain_exactly(include(id: mi_id(group_message), isRead: true))

    request_chat('read-all')
    expect(response).to have_http_status(204)
    request_chat('history')
    expect(response.parsed_body).to contain_exactly(include(id: mi_id(message), isRead: true))
  end

  it 'uses the last undeleted visible message in history' do
    conversation = direct_conversation
    previous = service.create_message(account, conversation, text: 'visible')
    deleted = service.create_message(account, conversation, text: 'deleted')
    service.delete_message(account, deleted)

    request_chat('history')

    expect(response.parsed_body.pluck(:id)).to eq([mi_id(previous)])
  end

  it 'leaves deleted messages out of the timelines, as they would not exist on Misskey' do
    conversation = direct_conversation
    kept = service.create_message(account, conversation, text: 'kept')
    service.delete_message(account, service.create_message(account, conversation, text: 'deleted'))
    room = group_conversation
    kept_in_room = service.create_message(account, room, text: 'kept')
    service.delete_message(account, service.create_message(account, room, text: 'deleted'))

    request_chat('messages/user-timeline', userId: mi_id(other.account))
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(kept)])

    request_chat('messages/room-timeline', roomId: mi_id(room))
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(kept_in_room)])
  end

  it 'gives every error the id that clients need to read it' do
    room = group_conversation

    request_chat('rooms/show', { roomId: mi_id(room) }, as_user: outsider)
    first = response.parsed_body[:error]
    request_chat('messages/room-timeline', { roomId: mi_id(room) }, as_user: outsider)

    expect(response).to have_http_status(400)
    expect(first).to include(code: 'NO_SUCH_ROOM', kind: 'client', id: '857ae02f-8759-4d20-9adb-6e95fffe4fd7')
    expect(response.parsed_body.dig(:error, :id)).to eq('c4d9f88c-9270-4632-b032-6ed8cee36f7f')
  end

  it 'updates and deletes a message through the shared chat service' do
    message = service.create_message(account, direct_conversation, text: 'before')

    request_chat('messages/update', messageId: mi_id(message), text: 'after')
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(text: 'after', editedAt: be_present)
    expect(message.reload.text).to eq('after')

    request_chat('messages/delete', messageId: mi_id(message))
    expect(response).to have_http_status(204)
    expect(message.reload).to be_deleted
  end

  it 'does not reveal or mutate a message outside the caller membership' do
    message = service.create_message(account, direct_conversation, text: 'secret')

    %w(show update delete react unreact).each do |action|
      request_chat("messages/#{action}", { messageId: mi_id(message), text: 'stolen', reaction: '👍' }, as_user: outsider)
      expect(response).to have_http_status(400), action
    end
    expect(message.reload.text).to eq('secret')
  end

  it 'rejects editing another member message' do
    message = service.create_message(other.account, direct_conversation, text: 'theirs')

    request_chat('messages/update', messageId: mi_id(message), text: 'stolen')

    expect(response).to have_http_status(400)
    expect(message.reload.text).to eq('theirs')
  end

  it 'adds and removes reactions and disallows reactions to the caller own message' do
    conversation = direct_conversation
    message = service.create_message(other.account, conversation, text: 'theirs')

    request_chat('messages/react', messageId: mi_id(message), reaction: '👍')
    expect(response).to have_http_status(204)
    expect(message.reactions.reload.pluck(:reaction)).to eq(['👍'])

    request_chat('messages/unreact', messageId: mi_id(message), reaction: '👍')
    expect(response).to have_http_status(204)
    expect(message.reactions.count).to be_zero

    own_message = service.create_message(account, conversation, text: 'mine')
    request_chat('messages/react', messageId: mi_id(own_message), reaction: '👍')
    expect(response).to have_http_status(400)
  end

  it 'searches only accessible messages and supports direct user and room filters' do
    direct_message = service.create_message(account, direct_conversation, text: 'needle direct')
    room = group_conversation
    room_message = service.create_message(account, room, text: 'needle room')
    secret = service.create_conversation(outsider.account, type: :group, title: 'Secret')
    service.create_message(outsider.account, secret, text: 'needle private')

    request_chat('messages/search', query: 'needle')
    expect(response.parsed_body.pluck(:id)).to contain_exactly(mi_id(direct_message), mi_id(room_message))

    request_chat('messages/search', query: 'needle', userId: mi_id(other.account))
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(direct_message)])

    request_chat('messages/search', query: 'needle', roomId: mi_id(room))
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(room_message)])

    request_chat('messages/search', query: 'needle', roomId: mi_id(secret))
    expect(response).to have_http_status(400)
  end

  it 'creates and renames a real group room' do
    request_chat('rooms/create', name: 'Room', description: 'About')
    expect(response).to have_http_status(200)
    room = ChatConversation.last
    expect(response.parsed_body).to include(id: mi_id(room), name: 'Room', ownerId: mi_id(account), description: 'About')

    request_chat('rooms/update', roomId: mi_id(room), name: 'Renamed')
    expect(response).to have_http_status(200)
    expect(room.reload.title).to eq('Renamed')

    request_chat('rooms/owned')
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(room)])
  end

  it 'invites a user and exposes only room metadata before joining' do
    room = group_conversation
    service.create_message(account, room, text: 'existing history')
    request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(other.account))
    expect(response).to have_http_status(200)
    invitation = ChatInvitation.last
    expect(response.parsed_body).to include(id: mi_id(invitation), roomId: mi_id(room), userId: mi_id(other.account))

    request_chat('rooms/invitations/outbox', roomId: mi_id(room))
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(invitation)])

    request_chat('rooms/invitations/inbox', {}, as_user: other)
    expect(response.parsed_body.pluck(:id)).to eq([mi_id(invitation)])

    request_chat('rooms/show', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(invitationExists: true)

    request_chat('messages/room-timeline', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(400)
  end

  it 'joins an invited room and exposes its members and timeline' do
    room = group_conversation
    invitation = service.invite(account, room, other.account)

    request_chat('rooms/join', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(204)
    expect(invitation.reload).to be_accepted

    request_chat('rooms/joining', {}, as_user: other)
    expect(response.parsed_body).to contain_exactly(include(roomId: mi_id(room), room: include(name: 'Room')))

    request_chat('rooms/members', roomId: mi_id(room))
    expect(response.parsed_body.pluck(:userId)).to contain_exactly(mi_id(other.account))

    request_chat('messages/create-to-room', { toRoomId: mi_id(room), text: 'joined' }, as_user: other)
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(toRoomId: mi_id(room), text: 'joined')
  end

  it 'does not list the owner as a room member' do
    room = group_conversation

    request_chat('rooms/members', roomId: mi_id(room))
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to be_empty
  end

  it 'mutes and leaves a joined room' do
    room = group_conversation
    service.accept_invitation(other.account, service.invite(account, room, other.account))

    request_chat('rooms/mute', { roomId: mi_id(room), mute: true }, as_user: other)
    expect(response).to have_http_status(204)
    expect(room.memberships.find_by!(account: other.account)).to be_muted

    request_chat('rooms/leave', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(204)
    expect(room.memberships.exists?(account: other.account)).to be(false)
  end

  it 'does not expose room metadata, members, or invitations to outsiders' do
    room = group_conversation

    %w(rooms/show rooms/members rooms/invitations/outbox).each do |endpoint|
      request_chat(endpoint, { roomId: mi_id(room) }, as_user: outsider)
      expect(response).to have_http_status(400), endpoint
    end
  end

  it 'archives rooms, rejects archived writes, and permits unarchive with a new name' do
    room = group_conversation
    request_chat('rooms/update', roomId: mi_id(room), isArchived: true)
    expect(response).to have_http_status(200)
    expect(room.reload).to be_archived

    request_chat('messages/create-to-room', toRoomId: mi_id(room), text: 'no')
    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('ROOM_IS_ARCHIVED')

    request_chat('rooms/update', roomId: mi_id(room), isArchived: false, name: 'Reopened')
    expect(response).to have_http_status(200)
    expect(room.reload).to_not be_archived
    expect(room.title).to eq('Reopened')
  end

  it 'restricts room updates and deletion to its owner' do
    room = group_conversation
    service.accept_invitation(other.account, service.invite(account, room, other.account))

    request_chat('rooms/update', { roomId: mi_id(room), name: 'stolen' }, as_user: other)
    expect(response).to have_http_status(400)
    request_chat('rooms/delete', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(400)

    request_chat('rooms/delete', roomId: mi_id(room))
    expect(response).to have_http_status(204)
    expect(ChatConversation.exists?(room.id)).to be(false)
  end

  it 'rejects and cancels pending invitations through their correct identities' do
    room = group_conversation
    invitation = service.invite(account, room, other.account)
    request_chat('rooms/invitations/reject', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(204)
    expect(invitation.reload).to be_rejected

    invitation = service.invite(account, room, other.account)
    request_chat('rooms/invitations/cancel', invitationId: mi_id(invitation))
    expect(response).to have_http_status(204)
    expect(invitation.reload).to be_cancelled
  end

  it 'hides an ignored invitation from the inbox while keeping it joinable' do
    room = group_conversation
    invitation = service.invite(account, room, other.account)

    request_chat('rooms/invitations/ignore', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(204)
    expect(invitation.reload).to be_pending
    expect(invitation).to be_ignored

    request_chat('rooms/invitations/inbox', {}, as_user: other)
    expect(response.parsed_body).to eq([])

    request_chat('rooms/join', { roomId: mi_id(room) }, as_user: other)
    expect(response).to have_http_status(204)
    expect(invitation.reload).to be_accepted
  end

  it 'attaches a caller-owned file and rejects another user file', :attachment_processing do
    media = Fabricate(:media_attachment, account: account, file: attachment_fixture('attachment.jpg'))
    request_chat('messages/create-to-user', toUserId: mi_id(other.account), fileId: mi_id(media))

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(fileId: mi_id(media), file: include(id: mi_id(media)))
    expect(ChatMessage.last.media_attachments).to contain_exactly(media)

    private_media = Fabricate(:media_attachment, account: other.account, file: attachment_fixture('attachment.jpg'))
    request_chat('messages/create-to-user', toUserId: mi_id(other.account), fileId: mi_id(private_media))
    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_FILE')
    expect(ChatMessage.count).to eq(1)
  end

  it 'accepts reusable Drive files through chat-specific pointers', :attachment_processing do
    Setting.drive_enabled = true
    file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))

    request_chat('messages/create-to-user', toUserId: mi_id(other.account), fileId: mi_id(file))

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(fileId: mi_id(file), file: include(id: mi_id(file)))
    expect(ChatMessage.last.media_attachments.first.drive_file_id).to eq(file.id)
  ensure
    Setting.drive_enabled = false
  end

  it 'checks MiAuth chat permissions independently from notes permissions' do
    grant = MisskeyCompat::MiAuth.issue_token(user, name: 'Chat reader', permissions: ['read:chat'])
    post '/api/chat/history', params: { i: grant.token }, as: :json
    expect(response).to have_http_status(200)

    post '/api/chat/messages/create-to-user', params: { i: grant.token, toUserId: mi_id(other.account), text: 'no' }, as: :json
    expect(response).to have_http_status(403)

    grant = MisskeyCompat::MiAuth.issue_token(user, name: 'Notes reader', permissions: ['read:notes'])
    post '/api/chat/history', params: { i: grant.token }, as: :json
    expect(response).to have_http_status(403)
  end

  it 'rejects ids and dates beyond the stored range as invalid parameters' do
    room = group_conversation
    [
      ['messages/room-timeline', { roomId: mi_id(room), sinceId: '99999999999999999999' }, 'sinceId'],
      ['messages/room-timeline', { roomId: mi_id(room), untilId: '0zzzzzzzzzzzzzzz' }, 'untilId'],
      ['messages/room-timeline', { roomId: '0zzzzzzzzzzzzzzz' }, 'roomId'],
      ['rooms/owned', { sinceId: '99999999999999999999' }, 'sinceId'],
      ['messages/room-timeline', { roomId: mi_id(room), sinceDate: 10**20 }, 'sinceDate'],
      ['messages/room-timeline', { roomId: mi_id(room), untilDate: -(10**20) }, 'untilDate'],
    ].each do |endpoint, params, key|
      request_chat(endpoint, params)

      expect(response).to have_http_status(400), "#{endpoint} #{params}"
      expect(response.parsed_body[:error]).to include(code: 'INVALID_PARAM', info: include(param: "#/properties/#{key}")), "#{endpoint} #{params}"
    end
  end

  it 'reads the history read state without a query for every message' do
    others = Array.new(3) { Fabricate(:user).account.tap { |peer| peer.user.settings[:chat_policy] = 'everyone' }.tap { |peer| peer.user.save! } }
    others.each { |peer| service.create_message(peer, service.create_conversation(account, type: :direct, account_ids: [peer.id]), text: 'unread') }

    queries = counted_queries(/FROM "chat_memberships" WHERE "chat_memberships"\."chat_conversation_id" = \$1 AND "chat_memberships"\."account_id" = \$2/) do
      request_chat('history')
    end

    expect(response.parsed_body.size).to eq(3)
    expect(response.parsed_body.pluck(:isRead)).to all(be(false))
    expect(queries).to be_empty
  end

  it 'looks up custom emojis once for a page of messages' do
    Fabricate(:custom_emoji, shortcode: 'blobcat')
    Fabricate(:custom_emoji, shortcode: 'neko')
    room = group_conversation
    service.create_message(account, room, text: 'hello :blobcat:')
    service.create_message(account, room, text: 'hello :neko:')
    service.create_message(account, room, text: 'plain')

    queries = counted_queries(/FROM "custom_emojis"/) { request_chat('messages/room-timeline', roomId: mi_id(room)) }

    expect(response.parsed_body.pluck(:emojis)).to contain_exactly(include('blobcat' => be_present), include('neko' => be_present), {})
    expect(queries.size).to eq(1)
  end

  it 'serializes joined rooms and room members without a query for every room or member' do
    count_for = lambda do |rooms|
      rooms.each { |room| service.accept_invitation(account, service.invite(other.account, room, account)) }
      counted_queries(/FROM "chat_|FROM "accounts"/) { request_chat('rooms/joining') }.size
    end

    single = count_for.call([service.create_conversation(other.account, type: :group, title: 'One')])
    several = count_for.call(Array.new(3) { |index| service.create_conversation(other.account, type: :group, title: "Room #{index}") })
    expect(several).to eq(single)

    room = group_conversation
    members = Array.new(3) { Fabricate(:user).account }
    first = members.first
    service.accept_invitation(first, service.invite(account, room, first))
    single = counted_queries(/FROM "chat_|FROM "accounts"/) { request_chat('rooms/members', roomId: mi_id(room)) }.size
    members.drop(1).each { |member| service.accept_invitation(member, service.invite(account, room, member)) }
    several = counted_queries(/FROM "chat_|FROM "accounts"/) { request_chat('rooms/members', roomId: mi_id(room)) }.size
    expect(response.parsed_body.size).to eq(3)
    expect(several).to eq(single)
  end

  it 'rejects missing and incorrectly typed parameters without mutating state' do
    request_chat('messages/show')
    expect(response).to have_http_status(400)
    request_chat('rooms/create', name: ['not a name'])
    expect(response).to have_http_status(400)
    request_chat('rooms/mute', roomId: mi_id(group_conversation), mute: 'false')
    expect(response).to have_http_status(400)
    expect(ChatMessage.count).to be_zero
  end
end
