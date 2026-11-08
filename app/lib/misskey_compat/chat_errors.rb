# frozen_string_literal: true

module MisskeyCompat::ChatErrors
  # rubocop:disable I18n/RailsI18n/DecorateString
  MESSAGES = {
    'ALREADY_MEMBER' => 'That user is already a member of this room.',
    'CANNOT_CHAT_WITH_USER' => 'This user does not accept your messages.',
    'CANNOT_INVITE_YOURSELF' => 'You cannot invite yourself.',
    'CONTENT_REQUIRED' => 'Content required. You need to set text or fileIds.',
    'INVALID_REACTION' => 'That reaction is not an emoji available on this server.',
    'INVALID_TEXT' => 'Invalid text.',
    'NO_SUCH_FILE' => 'No such file.',
    'NO_SUCH_INVITATION' => 'No such invitation.',
    'NO_SUCH_MEMBER' => 'No such removable member.',
    'NO_SUCH_MESSAGE' => 'No such message.',
    'NO_SUCH_ROOM' => 'No such room.',
    'NO_SUCH_USER' => 'No such user.',
    'RECIPIENT_IS_SUSPENDED' => 'You cannot send a message because this user is suspended.',
    'RECIPIENT_IS_YOURSELF' => 'You can not send a message to yourself.',
    'ROOM_DELETED' => 'This room was deleted.',
    'ROOM_IS_ARCHIVED' => 'This room is archived.',
    'ROOM_IS_FULL' => 'This room is full.',
    'TOO_MANY_REACTIONS' => 'This message cannot have any more reactions.',
    'USER_IS_SUSPENDED' => 'You cannot invite this user because they are suspended.',
    'YOU_ARE_BLOCKING' => 'You cannot invite a user you are blocking.',
    'YOU_HAVE_BEEN_BLOCKED' => 'You cannot send a message because you have been blocked by this user.',
  }.freeze

  INVITATION_MESSAGES = {
    'CANNOT_CHAT_WITH_USER' => 'This user does not accept invitations.',
    'YOU_HAVE_BEEN_BLOCKED' => 'You cannot invite this user because you have been blocked by them.',
  }.freeze
  # rubocop:enable I18n/RailsI18n/DecorateString

  IDS = {
    'show' => { 'NO_SUCH_MESSAGE' => '3710865b-1848-4da9-8d61-cfed15510b93' },
    'update' => {
      'INVALID_TEXT' => 'f6f8f5d4-1f37-4d3f-9e3b-4e1b4f8a2c71',
      'NO_SUCH_MESSAGE' => '31846552-b85d-4908-808f-64bf91000151',
      'ROOM_IS_ARCHIVED' => 'a1c94d37-2e58-4b06-8f1d-6d0b9e47c352',
    },
    'destroy' => { 'NO_SUCH_MESSAGE' => '36b67f0e-66a6-414b-83df-992a55294f17' },
    'react' => {
      'INVALID_REACTION' => '140ddc7a-276d-42b5-80ef-7aae6c0a8114',
      'NO_SUCH_MESSAGE' => '9b5839b9-0ba0-4351-8c35-37082093d200',
      'ROOM_IS_ARCHIVED' => '3d8c5e91-0f47-4a2b-86d3-c94e1b7a5f08',
      'TOO_MANY_REACTIONS' => '635702f5-0dfd-40c3-b669-1d6922055b20',
    },
    'unreact' => {
      'NO_SUCH_MESSAGE' => 'c39ea42f-e3ca-428a-ad57-390e0a711595',
      'ROOM_IS_ARCHIVED' => '92b7e6c4-5a13-4f80-a7d9-08f3e2c1b6d5',
    },
    'create_to_room' => {
      'CONTENT_REQUIRED' => '340517b7-6d04-42c0-bac1-37ee804e3594',
      'NO_SUCH_FILE' => 'b6accbd3-1d7b-4d9f-bdb7-eb185bac06db',
      'NO_SUCH_ROOM' => '8098520d-2da5-4e8f-8ee1-df78b55a4ec6',
      'ROOM_IS_ARCHIVED' => '5b6e1f2a-7c0d-4e39-9a41-2f8d3c6b7e10',
      'TOO_MANY_FILES' => 'c202ecbf-65fe-402a-8dd6-d257ea82cf70',
    },
    'create_to_user' => {
      'CANNOT_CHAT_WITH_USER' => 'fcaaed42-3f5a-4246-a08d-18736819e76b',
      'CONTENT_REQUIRED' => '25587321-b0e6-449c-9239-f8925092942c',
      'NO_SUCH_FILE' => '4372b8e2-185d-4146-8749-2f68864a3e5f',
      'NO_SUCH_USER' => '11795c64-40ea-4198-b06e-3c873ed9039d',
      'RECIPIENT_IS_SUSPENDED' => 'b9febcb3-1b46-4b4a-b8ce-8d695d3bd474',
      'RECIPIENT_IS_YOURSELF' => '17e2ba79-e22a-4cbc-bf91-d327643f4a7e',
      'TOO_MANY_FILES' => 'e577e5c3-5cae-4251-ba3c-d3a8f8e25c5f',
      'YOU_HAVE_BEEN_BLOCKED' => 'c15a5199-7422-4968-941a-2a462c478f7d',
    },
    'user_timeline' => { 'NO_SUCH_USER' => '11795c64-40ea-4198-b06e-3c873ed9039d' },
    'room_timeline' => { 'NO_SUCH_ROOM' => 'c4d9f88c-9270-4632-b032-6ed8cee36f7f' },
    'search' => { 'NO_SUCH_ROOM' => '460b3669-81b0-4dc9-a997-44442141bf83' },
    'show_room' => {
      'NO_SUCH_ROOM' => '857ae02f-8759-4d20-9adb-6e95fffe4fd7',
      'ROOM_DELETED' => '688e3c65-58d2-4a50-8098-eb9b5e48fdec',
    },
    'room_members' => { 'NO_SUCH_ROOM' => '7b9fe84c-eafc-4d21-bf89-485458ed2c18' },
    'update_room' => {
      'NO_SUCH_ROOM' => 'fcdb0f92-bda6-47f9-bd05-343e0e020932',
      'ROOM_IS_ARCHIVED' => '8655493b-6d45-4466-95ec-c8c38ddae472',
    },
    'destroy_room' => { 'NO_SUCH_ROOM' => 'd4e3753d-97bf-4a19-ab8e-21080fbc0f4b' },
    'mute_room' => { 'NO_SUCH_ROOM' => 'c2cde4eb-8d0f-42f1-8f2f-c4d6bfc8e5df' },
    'leave_room' => { 'NO_SUCH_ROOM' => 'cb7f3179-50e8-4389-8c30-dbe2650a67c9' },
    'kick_member' => {
      'NO_SUCH_MEMBER' => 'b4c87e54-c36a-40f4-99c7-b72032c48482',
      'NO_SUCH_ROOM' => '932260a0-ccf0-4caf-87be-3e9cccd12c2f',
    },
    'join_room' => {
      'NO_SUCH_ROOM' => '84416476-5ce8-4a2c-b568-9569f1b10733',
      'ROOM_IS_ARCHIVED' => 'c60a4f18-d3b2-4e75-9c06-7a1e58d3f2b9',
      'ROOM_IS_FULL' => '56d5a1da-4d30-4f7d-a931-f62e746533f9',
    },
    'create_invitation' => {
      'ALREADY_MEMBER' => 'a10a39b2-9ecb-4c77-8827-028bc550f977',
      'CANNOT_CHAT_WITH_USER' => 'fcaaed42-3f5a-4246-a08d-18736819e76b',
      'CANNOT_INVITE_YOURSELF' => '88605621-e640-4d2d-a96d-168b598f0c67',
      'NO_SUCH_ROOM' => '916f9507-49ba-4e90-b57f-1fd4deaa47a5',
      'NO_SUCH_USER' => '167a1ccf-d9ab-415e-941d-d08f28b2ca07',
      'ROOM_IS_ARCHIVED' => 'b41cd32a-8b2a-4662-ae54-bc5cbb057afa',
      'ROOM_IS_FULL' => '579fc80c-985c-45d1-b7f2-8022083dfa40',
      'USER_IS_SUSPENDED' => 'c2789971-48e2-41ac-b4f4-1304696987f7',
      'YOU_ARE_BLOCKING' => '9f802721-ad05-411c-806a-e9367ab1facf',
      'YOU_HAVE_BEEN_BLOCKED' => 'a3fc0535-5d74-4106-8b78-3f6ee467baca',
    },
    'cancel_invitation' => { 'NO_SUCH_INVITATION' => '8c8f38f0-3b7e-4f5e-9c6d-2e3f4a5b6c7d' },
    'ignore_invitation' => { 'NO_SUCH_ROOM' => '5130557e-5a11-4cfb-9cc5-fe60cda5de0d' },
    'reject_invitation' => { 'NO_SUCH_ROOM' => '5130557e-5a11-4cfb-9cc5-fe60cda5de0d' },
    'invitations_outbox' => { 'NO_SUCH_ROOM' => 'a3c6b309-9717-4316-ae94-a69b53437237' },
  }.freeze

  SERVICE_ERROR_CODES = {
    'Account is already a member' => 'ALREADY_MEMBER',
    'Archived conversations are read-only' => 'ROOM_IS_ARCHIVED',
    'Deleted messages cannot be edited' => 'NO_SUCH_MESSAGE',
    'Deleted messages cannot receive reactions' => 'NO_SUCH_MESSAGE',
    'One or more media attachments were not found' => 'NO_SUCH_FILE',
    'The group has too many members' => 'ROOM_IS_FULL',
    'The message has too many reactions' => 'TOO_MANY_REACTIONS',
    'The owner cannot leave the room' => 'NO_SUCH_ROOM',
  }.freeze

  CLOSEST_SERVICE_ERROR_CODES = {
    'One or more media attachments are still being processed' => 'NO_SUCH_FILE',
    'Rooms cannot be deleted while chat history is preserved' => 'NO_SUCH_ROOM',
    'This message can no longer be edited' => 'NO_SUCH_MESSAGE',
  }.freeze

  FEDERATION_DISABLED = 'Chat federation is disabled'
  FEDERATION_DISABLED_CODES = {
    'create_invitation' => 'NO_SUCH_USER',
    'create_to_room' => 'NO_SUCH_ROOM',
    'create_to_user' => 'CANNOT_CHAT_WITH_USER',
    'join_room' => 'NO_SUCH_ROOM',
    'leave_room' => 'NO_SUCH_ROOM',
    'react' => 'NO_SUCH_MESSAGE',
    'reject_invitation' => 'NO_SUCH_ROOM',
    'update' => 'NO_SUCH_MESSAGE',
  }.freeze

  def self.id(action, code)
    IDS.dig(action, code)
  end

  def self.message(action, code)
    return INVITATION_MESSAGES.fetch(code, MESSAGES.fetch(code)) if action == 'create_invitation'

    MESSAGES.fetch(code)
  end

  def self.closest_code(action, service_message)
    return FEDERATION_DISABLED_CODES[action] if service_message == FEDERATION_DISABLED

    CLOSEST_SERVICE_ERROR_CODES[service_message]
  end
end
