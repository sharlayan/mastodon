# frozen_string_literal: true

require 'rails_helper'

# The expected messages, codes and ids are copied from the endpoints of CherryPick. Clients written for it read
# them, so each refusal has to look the same there and here. Every one is reached by a real request.
RSpec.describe 'Misskey-compat chat errors' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:other) { Fabricate(:user) }
  let(:outsider) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:service) { Sharlayan::ChatService.new }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/member', inbox_url: 'https://remote.test/users/member/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:missing_id) { MisskeyCompat::MiId.encode(1_234_567) }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.misskey_compat_enabled = true
    Setting.chat_enabled = true
    Setting.chat_soft_delete_enabled = false
    Setting.chat_federation_enabled = true
    other.settings[:chat_policy] = 'everyone'
    other.settings[:chat_allow_group_invites] = true
    other.save!
    outsider.settings[:chat_allow_group_invites] = true
    outsider.save!
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.chat_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_federation_enabled = true
    Setting.chat_max_group_members = 50
    Setting.chat_max_attachments = 4
  end

  def request_chat(endpoint, params = {}, as_user: nil, **values)
    access_token = as_user ? Fabricate(:accessible_access_token, resource_owner_id: as_user.id, scopes: 'read write') : token
    post "/api/chat/#{endpoint}", params: params.merge(values).merge(i: access_token.token), as: :json
  end

  def expect_refusal(message, code, id)
    expect(response).to have_http_status(400)
    expect(response.parsed_body).to eq('error' => { 'message' => message, 'code' => code, 'id' => id, 'kind' => 'client' })
  end

  def mi_id(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  def direct_conversation
    service.create_conversation(account, type: :direct, account_ids: [other.account.id])
  end

  def room
    @room ||= service.create_conversation(account, type: :group, title: 'Room')
  end

  def room_with_other
    service.accept_invitation(other.account, service.invite(account, room, other.account))
    room
  end

  def message_from_other
    service.create_message(other.account, direct_conversation, text: 'theirs')
  end

  def message_from_me
    service.create_message(account, direct_conversation, text: 'mine')
  end

  def archive(conversation)
    service.archive(account, conversation, archived: true)
  end

  def media_file(owner = account)
    Fabricate(:media_attachment, account: owner, file: attachment_fixture('attachment.jpg'))
  end

  describe 'messages/react' do
    let(:no_such_message) { ['No such message.', 'NO_SUCH_MESSAGE', '9b5839b9-0ba0-4351-8c35-37082093d200'] }

    it 'refuses a message that its sender has deleted' do
      message = message_from_other
      service.delete_message(other.account, message)

      request_chat('messages/react', messageId: mi_id(message), reaction: '👍')

      expect_refusal(*no_such_message)
      expect(message.reactions.reload).to be_empty
    end

    it 'refuses the caller own message' do
      request_chat('messages/react', messageId: mi_id(message_from_me), reaction: '👍')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message that does not exist' do
      request_chat('messages/react', messageId: missing_id, reaction: '👍')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message outside the conversations of the caller' do
      request_chat('messages/react', { messageId: mi_id(message_from_other), reaction: '👍' }, as_user: outsider)

      expect_refusal(*no_such_message)
    end

    it 'refuses a message from someone who has blocked the caller' do
      message = message_from_other
      other.account.block!(account)

      request_chat('messages/react', messageId: mi_id(message), reaction: '👍')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message in an archived room' do
      message = service.create_message(other.account, room_with_other, text: 'theirs')
      archive(room)

      request_chat('messages/react', messageId: mi_id(message), reaction: '👍')

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', '3d8c5e91-0f47-4a2b-86d3-c94e1b7a5f08')
    end

    it 'refuses another reaction once the message has as many as it can have' do
      message = message_from_other
      emojis = StatusReactionValidator::SUPPORTED_EMOJIS.first(101)
      emojis.first(100).each { |emoji| message.reactions.create!(account: other.account, reaction: emoji) }

      request_chat('messages/react', messageId: mi_id(message), reaction: emojis.last)

      expect_refusal('This message cannot have any more reactions.', 'TOO_MANY_REACTIONS', '635702f5-0dfd-40c3-b669-1d6922055b20')
    end

    it 'refuses an emoji that this server does not have' do
      message = message_from_other

      request_chat('messages/react', messageId: mi_id(message), reaction: ':no_such_emoji:')

      expect_refusal('That reaction is not an emoji available on this server.', 'INVALID_REACTION', '140ddc7a-276d-42b5-80ef-7aae6c0a8114')
    end

    it 'refuses text that is not an emoji' do
      request_chat('messages/react', messageId: mi_id(message_from_other), reaction: 'not an emoji')

      expect_refusal('That reaction is not an emoji available on this server.', 'INVALID_REACTION', '140ddc7a-276d-42b5-80ef-7aae6c0a8114')
    end

    it 'says what happened with the closest code when federation is off, which CherryPick has no setting for' do
      room_with_other.memberships.create!(account: remote)
      message = service.create_message(other.account, room, text: 'theirs')
      Setting.chat_federation_enabled = false

      request_chat('messages/react', messageId: mi_id(message), reaction: '👍')

      expect_refusal('Chat federation is disabled', 'NO_SUCH_MESSAGE', '9b5839b9-0ba0-4351-8c35-37082093d200')
    end
  end

  describe 'messages/unreact' do
    let(:no_such_message) { ['No such message.', 'NO_SUCH_MESSAGE', 'c39ea42f-e3ca-428a-ad57-390e0a711595'] }

    it 'refuses a message that does not exist' do
      request_chat('messages/unreact', messageId: missing_id, reaction: '👍')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message outside the conversations of the caller' do
      request_chat('messages/unreact', { messageId: mi_id(message_from_other), reaction: '👍' }, as_user: outsider)

      expect_refusal(*no_such_message)
    end

    it 'refuses a message in an archived room' do
      message = service.create_message(other.account, room_with_other, text: 'theirs')
      service.react(account, message, '👍')
      archive(room)

      request_chat('messages/unreact', messageId: mi_id(message), reaction: '👍')

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', '92b7e6c4-5a13-4f80-a7d9-08f3e2c1b6d5')
      expect(message.reactions.reload.count).to eq(1)
    end
  end

  describe 'messages/update' do
    let(:no_such_message) { ['No such message.', 'NO_SUCH_MESSAGE', '31846552-b85d-4908-808f-64bf91000151'] }

    it 'refuses a deleted message' do
      message = message_from_me
      service.delete_message(account, message)

      request_chat('messages/update', messageId: mi_id(message), text: 'after')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message from someone else' do
      message = message_from_other

      request_chat('messages/update', messageId: mi_id(message), text: 'stolen')

      expect_refusal(*no_such_message)
      expect(message.reload.text).to eq('theirs')
    end

    it 'refuses a message that does not exist' do
      request_chat('messages/update', messageId: missing_id, text: 'after')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message to someone who has blocked the caller' do
      message = message_from_me
      other.account.block!(account)

      request_chat('messages/update', messageId: mi_id(message), text: 'after')

      expect_refusal(*no_such_message)
    end

    it 'refuses a message in an archived room' do
      message = service.create_message(account, room, text: 'mine')
      archive(room)

      request_chat('messages/update', messageId: mi_id(message), text: 'after')

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', 'a1c94d37-2e58-4b06-8f1d-6d0b9e47c352')
    end

    it 'refuses empty text' do
      request_chat('messages/update', messageId: mi_id(message_from_me), text: '   ')

      expect_refusal('Invalid text.', 'INVALID_TEXT', 'f6f8f5d4-1f37-4d3f-9e3b-4e1b4f8a2c71')
    end

    it 'says what happened with the closest code when the time to edit is over, which CherryPick has no limit for' do
      message = message_from_me
      message.update!(created_at: 2.days.ago)

      request_chat('messages/update', messageId: mi_id(message), text: 'after')

      expect_refusal('This message can no longer be edited', 'NO_SUCH_MESSAGE', '31846552-b85d-4908-808f-64bf91000151')
    end

    it 'says what happened with the closest code when federation is off' do
      room.memberships.create!(account: remote)
      message = service.create_message(account, room, text: 'mine')
      Setting.chat_federation_enabled = false

      request_chat('messages/update', messageId: mi_id(message), text: 'after')

      expect_refusal('Chat federation is disabled', 'NO_SUCH_MESSAGE', '31846552-b85d-4908-808f-64bf91000151')
    end
  end

  describe 'messages/delete' do
    let(:no_such_message) { ['No such message.', 'NO_SUCH_MESSAGE', '36b67f0e-66a6-414b-83df-992a55294f17'] }

    it 'refuses a message from someone else' do
      message = message_from_other

      request_chat('messages/delete', messageId: mi_id(message))

      expect_refusal(*no_such_message)
      expect(message.reload).to_not be_deleted
    end

    it 'refuses a message that does not exist' do
      request_chat('messages/delete', messageId: missing_id)

      expect_refusal(*no_such_message)
    end
  end

  describe 'messages/show' do
    let(:no_such_message) { ['No such message.', 'NO_SUCH_MESSAGE', '3710865b-1848-4da9-8d61-cfed15510b93'] }

    it 'refuses a message that does not exist' do
      request_chat('messages/show', messageId: missing_id)

      expect_refusal(*no_such_message)
    end

    it 'refuses a message outside the conversations of the caller' do
      request_chat('messages/show', { messageId: mi_id(message_from_other) }, as_user: outsider)

      expect_refusal(*no_such_message)
    end
  end

  describe 'messages/create-to-room' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', '8098520d-2da5-4e8f-8ee1-df78b55a4ec6'] }
    let(:no_such_file) { ['No such file.', 'NO_SUCH_FILE', 'b6accbd3-1d7b-4d9f-bdb7-eb185bac06db'] }

    it 'refuses a room that does not exist' do
      request_chat('messages/create-to-room', toRoomId: missing_id, text: 'hello')

      expect_refusal(*no_such_room)
    end

    it 'refuses a room the caller is not in' do
      request_chat('messages/create-to-room', { toRoomId: mi_id(room), text: 'hello' }, as_user: outsider)

      expect_refusal(*no_such_room)
    end

    it 'refuses an archived room' do
      archive(room)

      request_chat('messages/create-to-room', toRoomId: mi_id(room), text: 'hello')

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', '5b6e1f2a-7c0d-4e39-9a41-2f8d3c6b7e10')
    end

    it 'refuses a message with neither text nor files' do
      request_chat('messages/create-to-room', toRoomId: mi_id(room))

      expect_refusal('Content required. You need to set text or fileIds.', 'CONTENT_REQUIRED', '340517b7-6d04-42c0-bac1-37ee804e3594')
    end

    it 'refuses a file that belongs to someone else', :attachment_processing do
      request_chat('messages/create-to-room', toRoomId: mi_id(room), fileId: mi_id(media_file(other.account)))

      expect_refusal(*no_such_file)
    end

    it 'refuses a file that is already attached to a message', :attachment_processing do
      media = media_file
      service.create_message(account, room, text: 'first', media_ids: [media.id])

      request_chat('messages/create-to-room', toRoomId: mi_id(room), fileId: mi_id(media))

      expect_refusal(*no_such_file)
    end

    it 'says what happened with the closest code when a file is still being processed, which CherryPick never has to wait for', :attachment_processing do
      media = media_file
      media.update!(processing: :in_progress)

      request_chat('messages/create-to-room', toRoomId: mi_id(room), fileId: mi_id(media))

      expect_refusal('One or more media attachments are still being processed', 'NO_SUCH_FILE', 'b6accbd3-1d7b-4d9f-bdb7-eb185bac06db')
    end

    it 'refuses more files than a message can have when the two ways of naming them add up to that' do
      request_chat('messages/create-to-room', toRoomId: mi_id(room), fileId: MisskeyCompat::MiId.encode(5), fileIds: (1..4).map { |id| MisskeyCompat::MiId.encode(id) })

      expect_refusal('A message can have up to 4 files.', 'TOO_MANY_FILES', 'c202ecbf-65fe-402a-8dd6-d257ea82cf70')
    end

    it 'refuses more files than this server allows' do
      Setting.chat_max_attachments = 2

      request_chat('messages/create-to-room', toRoomId: mi_id(room), fileIds: (1..3).map { |id| MisskeyCompat::MiId.encode(id) })

      expect_refusal('A message can have up to 2 files.', 'TOO_MANY_FILES', 'c202ecbf-65fe-402a-8dd6-d257ea82cf70')
    end

    it 'calls too long a list of files an invalid parameter, as the schema of CherryPick does' do
      request_chat('messages/create-to-room', toRoomId: mi_id(room), fileIds: (1..5).map { |id| MisskeyCompat::MiId.encode(id) })

      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(code: 'INVALID_PARAM', id: '3d81ceae-475f-4600-b2a8-2bc116157532')
      expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/fileIds')
    end

    it 'says what happened with the closest code when federation is off' do
      room.memberships.create!(account: remote)
      Setting.chat_federation_enabled = false

      request_chat('messages/create-to-room', toRoomId: mi_id(room), text: 'hello')

      expect_refusal('Chat federation is disabled', 'NO_SUCH_ROOM', '8098520d-2da5-4e8f-8ee1-df78b55a4ec6')
    end
  end

  describe 'messages/create-to-user' do
    let(:cannot_chat) { ['This user does not accept your messages.', 'CANNOT_CHAT_WITH_USER', 'fcaaed42-3f5a-4246-a08d-18736819e76b'] }

    it 'refuses the caller as the recipient' do
      request_chat('messages/create-to-user', toUserId: mi_id(account), text: 'hello')

      expect_refusal('You can not send a message to yourself.', 'RECIPIENT_IS_YOURSELF', '17e2ba79-e22a-4cbc-bf91-d327643f4a7e')
    end

    it 'refuses a recipient that does not exist' do
      request_chat('messages/create-to-user', toUserId: missing_id, text: 'hello')

      expect_refusal('No such user.', 'NO_SUCH_USER', '11795c64-40ea-4198-b06e-3c873ed9039d')
    end

    it 'refuses a suspended recipient' do
      other.account.suspend!

      request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

      expect_refusal('You cannot send a message because this user is suspended.', 'RECIPIENT_IS_SUSPENDED', 'b9febcb3-1b46-4b4a-b8ce-8d695d3bd474')
    end

    it 'refuses a recipient who has blocked the caller' do
      other.account.block!(account)

      request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

      expect_refusal('You cannot send a message because you have been blocked by this user.', 'YOU_HAVE_BEEN_BLOCKED', 'c15a5199-7422-4968-941a-2a462c478f7d')
    end

    it 'refuses a recipient whom the caller is blocking' do
      account.block!(other.account)

      request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

      expect_refusal(*cannot_chat)
    end

    it 'refuses a recipient who does not take messages from the caller' do
      other.settings[:chat_policy] = 'none'
      other.save!

      request_chat('messages/create-to-user', toUserId: mi_id(other.account), text: 'hello')

      expect_refusal(*cannot_chat)
      expect(ChatConversation.count).to be_zero
    end

    it 'refuses a message with neither text nor files' do
      request_chat('messages/create-to-user', toUserId: mi_id(other.account))

      expect_refusal('Content required. You need to set text or fileIds.', 'CONTENT_REQUIRED', '25587321-b0e6-449c-9239-f8925092942c')
    end

    it 'refuses a file that belongs to someone else', :attachment_processing do
      request_chat('messages/create-to-user', toUserId: mi_id(other.account), fileId: mi_id(media_file(other.account)))

      expect_refusal('No such file.', 'NO_SUCH_FILE', '4372b8e2-185d-4146-8749-2f68864a3e5f')
    end

    it 'refuses more files than a message can have' do
      request_chat('messages/create-to-user', toUserId: mi_id(other.account), fileId: MisskeyCompat::MiId.encode(5), fileIds: (1..4).map { |id| MisskeyCompat::MiId.encode(id) })

      expect_refusal('A message can have up to 4 files.', 'TOO_MANY_FILES', 'e577e5c3-5cae-4251-ba3c-d3a8f8e25c5f')
    end

    it 'says what happened with the closest code when federation is off and the recipient is elsewhere' do
      Setting.chat_federation_enabled = false

      request_chat('messages/create-to-user', toUserId: mi_id(remote), text: 'hello')

      expect_refusal('Chat federation is disabled', 'CANNOT_CHAT_WITH_USER', 'fcaaed42-3f5a-4246-a08d-18736819e76b')
    end
  end

  describe 'reading messages' do
    it 'refuses the timeline with a user who does not exist' do
      request_chat('messages/user-timeline', userId: missing_id)

      expect_refusal('No such user.', 'NO_SUCH_USER', '11795c64-40ea-4198-b06e-3c873ed9039d')
    end

    it 'refuses the timeline of a room the caller is not in' do
      request_chat('messages/room-timeline', { roomId: mi_id(room) }, as_user: outsider)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', 'c4d9f88c-9270-4632-b032-6ed8cee36f7f')
    end

    it 'refuses a search in a room the caller is not in' do
      request_chat('messages/search', { query: 'hello', roomId: mi_id(room) }, as_user: outsider)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', '460b3669-81b0-4dc9-a997-44442141bf83')
    end
  end

  describe 'rooms/show' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', '857ae02f-8759-4d20-9adb-6e95fffe4fd7'] }

    it 'refuses a room that does not exist' do
      request_chat('rooms/show', roomId: missing_id)

      expect_refusal(*no_such_room)
    end

    it 'refuses a room the caller is not in' do
      request_chat('rooms/show', { roomId: mi_id(room) }, as_user: outsider)

      expect_refusal(*no_such_room)
    end

    it 'tells someone who was in a deleted room that it was deleted' do
      room_id = mi_id(room_with_other)
      service.destroy_conversation(account, room)

      request_chat('rooms/show', { roomId: room_id }, as_user: other)

      expect_refusal('This room was deleted.', 'ROOM_DELETED', '688e3c65-58d2-4a50-8098-eb9b5e48fdec')
    end

    it 'does not tell anyone else that a deleted room ever existed' do
      room_id = mi_id(room_with_other)
      service.destroy_conversation(account, room)

      request_chat('rooms/show', { roomId: room_id }, as_user: outsider)

      expect_refusal(*no_such_room)
    end
  end

  describe 'rooms/members' do
    it 'refuses a room the caller is not in' do
      request_chat('rooms/members', { roomId: mi_id(room) }, as_user: outsider)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', '7b9fe84c-eafc-4d21-bf89-485458ed2c18')
    end
  end

  describe 'rooms/update' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', 'fcdb0f92-bda6-47f9-bd05-343e0e020932'] }

    it 'refuses a member who does not own the room' do
      request_chat('rooms/update', { roomId: mi_id(room_with_other), name: 'stolen' }, as_user: other)

      expect_refusal(*no_such_room)
      expect(room.reload.title).to eq('Room')
    end

    it 'refuses a room the caller is not in' do
      request_chat('rooms/update', { roomId: mi_id(room), name: 'stolen' }, as_user: outsider)

      expect_refusal(*no_such_room)
    end

    it 'refuses to rename an archived room' do
      archive(room)

      request_chat('rooms/update', roomId: mi_id(room), name: 'renamed')

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', '8655493b-6d45-4466-95ec-c8c38ddae472')
    end
  end

  describe 'rooms/delete' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', 'd4e3753d-97bf-4a19-ab8e-21080fbc0f4b'] }

    it 'refuses a member who does not own the room' do
      request_chat('rooms/delete', { roomId: mi_id(room_with_other) }, as_user: other)

      expect_refusal(*no_such_room)
      expect(ChatConversation.exists?(room.id)).to be(true)
    end

    it 'refuses a room that does not exist' do
      request_chat('rooms/delete', roomId: missing_id)

      expect_refusal(*no_such_room)
    end
  end

  describe 'rooms/mute' do
    it 'refuses a room the caller is not in' do
      request_chat('rooms/mute', { roomId: mi_id(room), mute: true }, as_user: outsider)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', 'c2cde4eb-8d0f-42f1-8f2f-c4d6bfc8e5df')
    end
  end

  describe 'rooms/leave' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', 'cb7f3179-50e8-4389-8c30-dbe2650a67c9'] }

    it 'refuses a room the caller is not in' do
      request_chat('rooms/leave', { roomId: mi_id(room) }, as_user: outsider)

      expect_refusal(*no_such_room)
    end

    it 'refuses the owner, who is not a member in CherryPick' do
      request_chat('rooms/leave', roomId: mi_id(room))

      expect_refusal(*no_such_room)
      expect(room.memberships.exists?(account: account)).to be(true)
    end
  end

  describe 'rooms/kick' do
    it 'refuses a member who does not own the room' do
      request_chat('rooms/kick', { roomId: mi_id(room_with_other), userId: mi_id(account) }, as_user: other)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', '932260a0-ccf0-4caf-87be-3e9cccd12c2f')
    end

    it 'refuses someone who is not in the room' do
      request_chat('rooms/kick', roomId: mi_id(room), userId: mi_id(outsider.account))

      expect_refusal('No such removable member.', 'NO_SUCH_MEMBER', 'b4c87e54-c36a-40f4-99c7-b72032c48482')
    end
  end

  describe 'rooms/join' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', '84416476-5ce8-4a2c-b568-9569f1b10733'] }

    it 'refuses without an invitation' do
      request_chat('rooms/join', { roomId: mi_id(room) }, as_user: other)

      expect_refusal(*no_such_room)
    end

    it 'refuses an archived room' do
      service.invite(account, room, other.account)
      archive(room)

      request_chat('rooms/join', { roomId: mi_id(room) }, as_user: other)

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', 'c60a4f18-d3b2-4e75-9c06-7a1e58d3f2b9')
    end

    it 'refuses a full room' do
      service.invite(account, room, other.account)
      service.accept_invitation(outsider.account, service.invite(account, room, outsider.account))
      Setting.chat_max_group_members = 2

      request_chat('rooms/join', { roomId: mi_id(room) }, as_user: other)

      expect_refusal('This room is full.', 'ROOM_IS_FULL', '56d5a1da-4d30-4f7d-a931-f62e746533f9')
    end

    it 'refuses when the one who sent the invitation has been blocked since' do
      service.invite(account, room, other.account)
      other.account.block!(account)

      request_chat('rooms/join', { roomId: mi_id(room) }, as_user: other)

      expect_refusal(*no_such_room)
    end
  end

  describe 'rooms/invitations/create' do
    let(:no_such_room) { ['No such room.', 'NO_SUCH_ROOM', '916f9507-49ba-4e90-b57f-1fd4deaa47a5'] }

    it 'refuses a room the caller is not in' do
      request_chat('rooms/invitations/create', { roomId: mi_id(room), userId: mi_id(other.account) }, as_user: outsider)

      expect_refusal(*no_such_room)
    end

    it 'refuses a member who does not own the room' do
      request_chat('rooms/invitations/create', { roomId: mi_id(room_with_other), userId: mi_id(outsider.account) }, as_user: other)

      expect_refusal(*no_such_room)
    end

    it 'refuses an archived room' do
      archive(room)

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(other.account))

      expect_refusal('This room is archived.', 'ROOM_IS_ARCHIVED', 'b41cd32a-8b2a-4662-ae54-bc5cbb057afa')
    end

    it 'refuses a full room' do
      service.invite(account, room, other.account)
      Setting.chat_max_group_members = 2

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(outsider.account))

      expect_refusal('This room is full.', 'ROOM_IS_FULL', '579fc80c-985c-45d1-b7f2-8022083dfa40')
    end

    it 'refuses the caller' do
      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(account))

      expect_refusal('You cannot invite yourself.', 'CANNOT_INVITE_YOURSELF', '88605621-e640-4d2d-a96d-168b598f0c67')
    end

    it 'refuses someone who does not exist' do
      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: missing_id)

      expect_refusal('No such user.', 'NO_SUCH_USER', '167a1ccf-d9ab-415e-941d-d08f28b2ca07')
    end

    it 'refuses someone suspended' do
      other.account.suspend!

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(other.account))

      expect_refusal('You cannot invite this user because they are suspended.', 'USER_IS_SUSPENDED', 'c2789971-48e2-41ac-b4f4-1304696987f7')
    end

    it 'refuses someone already in the room' do
      request_chat('rooms/invitations/create', roomId: mi_id(room_with_other), userId: mi_id(other.account))

      expect_refusal('That user is already a member of this room.', 'ALREADY_MEMBER', 'a10a39b2-9ecb-4c77-8827-028bc550f977')
    end

    it 'refuses someone who has blocked the caller' do
      other.account.block!(account)

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(other.account))

      expect_refusal('You cannot invite this user because you have been blocked by them.', 'YOU_HAVE_BEEN_BLOCKED', 'a3fc0535-5d74-4106-8b78-3f6ee467baca')
    end

    it 'refuses someone whom the caller is blocking' do
      account.block!(other.account)

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(other.account))

      expect_refusal('You cannot invite a user you are blocking.', 'YOU_ARE_BLOCKING', '9f802721-ad05-411c-806a-e9367ab1facf')
    end

    it 'says what happened with the closest code when someone takes no invitations, which CherryPick has no setting for' do
      other.settings[:chat_allow_group_invites] = false
      other.save!

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(other.account))

      expect_refusal('This user does not accept invitations.', 'CANNOT_CHAT_WITH_USER', 'fcaaed42-3f5a-4246-a08d-18736819e76b')
    end

    it 'says what happened with the closest code when federation is off and the invitee is elsewhere' do
      Setting.chat_federation_enabled = false

      request_chat('rooms/invitations/create', roomId: mi_id(room), userId: mi_id(remote))

      expect_refusal('Chat federation is disabled', 'NO_SUCH_USER', '167a1ccf-d9ab-415e-941d-d08f28b2ca07')
    end
  end

  describe 'answering invitations' do
    it 'refuses to cancel an invitation that does not exist' do
      request_chat('rooms/invitations/cancel', invitationId: missing_id)

      expect_refusal('No such invitation.', 'NO_SUCH_INVITATION', '8c8f38f0-3b7e-4f5e-9c6d-2e3f4a5b6c7d')
    end

    it 'refuses to cancel an invitation someone else sent' do
      invitation = service.invite(account, room, other.account)

      request_chat('rooms/invitations/cancel', { invitationId: mi_id(invitation) }, as_user: outsider)

      expect_refusal('No such invitation.', 'NO_SUCH_INVITATION', '8c8f38f0-3b7e-4f5e-9c6d-2e3f4a5b6c7d')
      expect(invitation.reload).to be_pending
    end

    it 'refuses to ignore without an invitation' do
      request_chat('rooms/invitations/ignore', { roomId: mi_id(room) }, as_user: other)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', '5130557e-5a11-4cfb-9cc5-fe60cda5de0d')
    end

    it 'refuses to reject without an invitation' do
      request_chat('rooms/invitations/reject', { roomId: mi_id(room) }, as_user: other)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', '5130557e-5a11-4cfb-9cc5-fe60cda5de0d')
    end

    it 'refuses the sent invitations of a room the caller does not own' do
      request_chat('rooms/invitations/outbox', { roomId: mi_id(room_with_other) }, as_user: other)

      expect_refusal('No such room.', 'NO_SUCH_ROOM', 'a3c6b309-9717-4316-ae94-a69b53437237')
    end
  end
end
