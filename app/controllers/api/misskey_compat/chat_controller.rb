# frozen_string_literal: true

class Api::MisskeyCompat::ChatController < Api::MisskeyCompat::BaseController
  READ_ACTIONS = %i(history user_timeline room_timeline show search owned_rooms joining_rooms room_members show_room invitations_inbox invitations_outbox).freeze
  WRITE_ACTIONS = %i(read_all create_to_user create_to_room update destroy react unreact create_room update_room destroy_room mute_room leave_room kick_member join_room create_invitation ignore_invitation reject_invitation cancel_invitation).freeze
  BOOLEAN_VALUES = [true, false].freeze
  NULLABLE_SEARCH_IDS = %i(userId roomId).freeze
  CREATE_MESSAGE_ACTIONS = %w(create_to_user create_to_room).freeze
  NONEMPTY_FIELDS = %i(name query reaction).freeze
  CHAT_ID_PARAMS = %i(messageId roomId toRoomId toUserId invitationId).freeze
  MAX_FILE_IDS = 4
  ROOM_PRELOADS = %i(owner_account invitations memberships).freeze
  MESSAGE_ACTIONS = %w(show update destroy react unreact).freeze
  REQUIRED_PARAMS = {
    user_timeline: %i(userId), room_timeline: %i(roomId), show: %i(messageId),
    create_to_user: %i(toUserId), create_to_room: %i(toRoomId), update: %i(messageId text),
    destroy: %i(messageId), react: %i(messageId reaction), unreact: %i(messageId reaction),
    search: %i(query), create_room: %i(name), room_members: %i(roomId), show_room: %i(roomId),
    update_room: %i(roomId), destroy_room: %i(roomId), mute_room: %i(roomId mute),
    leave_room: %i(roomId), kick_member: %i(roomId userId), join_room: %i(roomId), invitations_outbox: %i(roomId),
    create_invitation: %i(roomId userId), ignore_invitation: %i(roomId),
    reject_invitation: %i(roomId), cancel_invitation: %i(invitationId)
  }.freeze

  requires_write_scope(*WRITE_ACTIONS)
  requires_misskey_permission('read:chat', *READ_ACTIONS)
  requires_misskey_permission('write:chat', *WRITE_ACTIONS)

  before_action :require_chat_enabled!
  before_action :require_user!
  before_action :decode_chat_ids!
  before_action :validate_chat_params!
  before_action :enforce_write_rate_limit!, only: WRITE_ACTIONS - [:read_all]
  before_action :enforce_search_rate_limit!, only: :search

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from Sharlayan::ChatService::Error, with: :render_chat_error
  rescue_from Sharlayan::ChatService::Forbidden, with: :render_chat_forbidden
  rescue_from MisskeyCompat::DriveFileResolver::NoSuchFileError do
    refuse('NO_SUCH_FILE')
  end
  rescue_from MisskeyCompat::DriveFileResolver::AmbiguousFileError do
    render_invalid_param('#/properties/fileId', 'ambiguous file id')
  end

  def history
    conversations = accessible_conversations.where(conversation_type: params[:room] ? :group : :direct)
    latest_ids = ChatMessage.visible.visible_to(current_account).where(chat_conversation_id: conversations.select(:id)).group(:chat_conversation_id).select('MAX(chat_messages.id)')
    messages = ChatMessage.where(id: latest_ids).order(id: :desc).limit(pagination_limit(default: 10, max: 100))
    messages = preload_messages(messages).to_a
    render json: MisskeyCompat::ChatSerializer.messages(messages, viewer: current_account).zip(messages).map { |serialized, message| serialized.merge(isRead: read_message?(message)) }
  end

  def read_all
    accessible_conversations.find_each { |conversation| chat_service.mark_read(current_account, conversation) }
    head 204
  end

  def user_timeline
    other = find_account!(:userId)
    conversation = direct_conversation_for(other.id)
    return render json: [] if conversation.nil?

    messages = paginate(conversation.messages.visible_to(current_account).visible, default: 10)
    chat_service.mark_read(current_account, conversation)
    render_messages(messages)
  end

  def room_timeline
    conversation = member_room!
    messages = paginate(conversation.messages.visible_to(current_account).visible, default: 10)
    chat_service.mark_read(current_account, conversation)
    render_messages(messages)
  end

  def show
    render json: serialize_message(find_message!)
  end

  def create_to_user
    recipient = Account.find(params[:toUserId])
    return refuse('RECIPIENT_IS_YOURSELF') if recipient.id == current_account.id
    return refuse('RECIPIENT_IS_SUSPENDED') if recipient.suspended?
    return unless valid_message_text?

    with_media_ids do |media_ids|
      render json: serialize_message(chat_service.create_direct_message(current_account, recipient, text: params[:text], media_ids: media_ids))
    end
  end

  def create_to_room
    conversation = member_room!(:toRoomId)
    return unless valid_message_text?

    with_media_ids do |media_ids|
      message = chat_service.create_message(current_account, conversation, text: params[:text], media_ids: media_ids)
      render json: serialize_message(message)
    end
  end

  def update
    message = find_message!
    return unless valid_message_text?(editing: true)

    render json: serialize_message(chat_service.update_message(current_account, message, text: params[:text]))
  end

  def destroy
    chat_service.delete_message(current_account, find_message!)
    head 204
  end

  def react
    chat_service.react(current_account, find_message!, normalized_reaction)
    head 204
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.is_a?(ChatMessageReaction)

    refuse('INVALID_REACTION')
  end

  def unreact
    chat_service.unreact(current_account, find_message!, normalized_reaction)
    head 204
  end

  def search
    room = member_room! if params[:roomId].present?
    messages = accessible_messages.visible.where('chat_messages.text ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].strip)}%")
    if params[:userId].present?
      conversation = direct_conversation_for(params[:userId])
      messages = messages.where(chat_conversation_id: conversation&.id)
    elsif room
      messages = messages.where(chat_conversation_id: room.id)
    end
    render_messages(messages.order(id: :desc).limit(pagination_limit(default: 10, max: 100)))
  end

  def create_room
    conversation = chat_service.create_conversation(current_account, type: :group, title: params[:name], description: params[:description])
    render json: serialize_room(conversation)
  end

  def owned_rooms
    rooms = accessible_conversations.chat_group.where(owner_account: current_account)
    render json: paginate(rooms).includes(ROOM_PRELOADS).map { |conversation| serialize_room(conversation) }
  end

  def joining_rooms
    memberships = ChatMembership.joins(:chat_conversation).where(account: current_account, chat_conversations: { conversation_type: :group }).where.not(role: :owner)
    render json: paginate(memberships).includes(:account, chat_conversation: ROOM_PRELOADS).map { |membership| serialize_membership(membership) }
  end

  def room_members
    memberships = paginate(member_room!.memberships.where.not(role: :owner))
    render json: memberships.includes(:account, chat_conversation: ROOM_PRELOADS).map { |membership| serialize_membership(membership) }
  end

  def show_room
    room = accessible_conversations.chat_group.find_by(id: params[:roomId])
    room ||= ChatConversation.chat_group.joins(:invitations).find_by(id: params[:roomId], chat_invitations: { invitee_account_id: current_account.id, state: :pending })
    return render json: serialize_room(room) if room

    refuse(chat_service.room_ending(current_account, params[:roomId]) == 'deleted' ? 'ROOM_DELETED' : 'NO_SUCH_ROOM')
  end

  def update_room
    room = member_room!
    attributes = {}
    attributes[:title] = params[:name] if params.key?(:name)
    attributes[:description] = params[:description] if params.key?(:description)
    room.transaction do
      chat_service.archive(current_account, room, archived: false) if params[:isArchived] == false
      chat_service.update_conversation(current_account, room, attributes) if attributes.present? || !params.key?(:isArchived)
      chat_service.archive(current_account, room, archived: true) if params[:isArchived] == true
    end
    render json: serialize_room(room)
  end

  def destroy_room
    chat_service.destroy_conversation(current_account, member_room!)
    head 204
  end

  def mute_room
    chat_service.mute(current_account, member_room!, muted: params[:mute])
    head 204
  end

  def leave_room
    chat_service.leave(current_account, member_room!)
    head 204
  end

  def join_room
    chat_service.accept_invitation(current_account, received_invitation!)
    head 204
  end

  def kick_member
    room = accessible_conversations.chat_group.find_by(id: params[:roomId], owner_account: current_account)
    return refuse('NO_SUCH_ROOM') if room.nil?

    member = room.memberships.where.not(account_id: current_account.id).find_by(account_id: params[:userId])
    return refuse('NO_SUCH_MEMBER') if member.nil?

    chat_service.kick(current_account, room, member.account)
    head 204
  end

  def invitations_inbox
    invitations = ChatInvitation.pending.from_available_inviters.where(invitee_account: current_account, ignored: false)
    render_invitations(invitations)
  end

  def invitations_outbox
    render_invitations(owned_room!.invitations.pending)
  end

  def create_invitation
    room = owned_room!
    invitee = Account.find(params[:userId])
    return refuse('CANNOT_INVITE_YOURSELF') if invitee.id == current_account.id
    return refuse('USER_IS_SUSPENDED') if invitee.suspended?

    render json: MisskeyCompat::ChatSerializer.invitation(chat_service.invite(current_account, room, invitee), viewer: current_account)
  end

  def ignore_invitation
    received_invitation!.update!(ignored: true)
    head 204
  end

  def reject_invitation
    chat_service.reject_invitation(current_account, received_invitation!)
    head 204
  end

  def cancel_invitation
    invitation = ChatInvitation.pending.where(inviter_account: current_account).find(params[:invitationId])
    chat_service.cancel_invitation(current_account, invitation)
    head 204
  end

  private

  def chat_service
    @chat_service ||= Sharlayan::ChatService.new
  end

  def require_chat_enabled!
    render_error('Chat is not available', 'ENDPOINT_DISABLED', 404) unless Setting.chat_enabled
  end

  def decode_chat_ids!
    CHAT_ID_PARAMS.each do |key|
      params[key] = MisskeyCompat::MiId.decode(params[key]) if params[key].is_a?(String)
    end
  end

  def validate_chat_params!
    return unless object_body!

    REQUIRED_PARAMS.fetch(action_name.to_sym, []).each do |key|
      return render_invalid_param("#/properties/#{key}", 'is required') unless params.key?(key)
    end

    (CHAT_ID_PARAMS + %i(userId fileId sinceId untilId)).each do |key|
      next unless params.key?(key)
      next if params[key].nil? && NULLABLE_SEARCH_IDS.include?(key) && action_name == 'search'

      return render_invalid_param("#/properties/#{key}", 'must be an id') unless compat_id?(params[key])
    end

    return render_invalid_param('#/properties/fileIds', 'must be a list of ids') if params.key?(:fileIds) && !(params[:fileIds].is_a?(Array) && params[:fileIds].all? { |id| compat_id?(id) })
    return render_invalid_param('#/properties/fileIds', "must have at most #{MAX_FILE_IDS} items") if params.key?(:fileIds) && params[:fileIds].size > MAX_FILE_IDS

    { name: 256, description: 1024, query: 256, reaction: 100, text: ChatMessage::MAX_TEXT_LENGTH }.each do |key, max|
      next unless params.key?(key)
      next if key == :text && params[key].nil? && CREATE_MESSAGE_ACTIONS.include?(action_name)

      value = params[key]
      return render_invalid_param("#/properties/#{key}", "must be a string of at most #{max} characters") unless value.is_a?(String) && value.length <= max
      return render_invalid_param("#/properties/#{key}", 'must not be empty') if NONEMPTY_FIELDS.include?(key) && value.strip.empty?
    end

    %i(room mute isArchived).each do |key|
      next unless params.key?(key)

      return render_invalid_param("#/properties/#{key}", 'must be a boolean') unless BOOLEAN_VALUES.include?(params[key])
    end

    return render_invalid_param('#/properties/limit', 'must be an integer between 1 and 100') if params.key?(:limit) && (!params[:limit].is_a?(Integer) || !params[:limit].between?(1, 100))

    %i(sinceDate untilDate).each do |key|
      return render_invalid_param("#/properties/#{key}", 'must be an integer') if params.key?(key) && !params[key].is_a?(Integer)
      return render_invalid_param("#/properties/#{key}", 'is out of range') if params.key?(key) && !compat_date?(params[key])
    end
  end

  def enforce_write_rate_limit!
    return if Setting.rate_limit_bypass_enabled && current_user.can_extra?(:bypass_rate_limit)

    rate_limited?(:chat_writes)
  end

  def enforce_search_rate_limit!
    rate_limited?(:chat_searches)
  end

  def accessible_conversations
    ChatConversation.for_account(current_account)
  end

  def accessible_messages
    ChatMessage.visible_to(current_account).where(chat_conversation_id: accessible_conversations.select(:id))
  end

  def direct_conversation_for(other_id)
    accessible_conversations.chat_direct.find_by(direct_key: [current_account.id, other_id.to_i].sort.join(':'))
  end

  def member_room!(key = :roomId)
    accessible_conversations.chat_group.find(params[key])
  end

  def owned_room!
    accessible_conversations.chat_group.where(owner_account: current_account).find(params[:roomId])
  end

  def received_invitation!
    ChatInvitation.pending.where(invitee_account: current_account).find_by!(chat_conversation_id: params[:roomId])
  end

  def find_message!
    accessible_messages.find(params[:messageId])
  end

  def find_account!(key)
    Account.without_suspended.find(params[key])
  end

  def paginate(scope, default: 30)
    table = scope.klass.arel_table
    scope = scope.where(table[:id].lt(params[:untilId])) if params[:untilId].present?
    scope = scope.where(table[:id].gt(params[:sinceId])) if params[:sinceId].present?
    scope = apply_compat_pagination_dates(scope)
    scope.reorder(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: default, max: 100))
  end

  def preload_messages(messages)
    messages.includes(:account, chat_conversation: [*ROOM_PRELOADS, :accounts], reactions: :account, media_attachments: :chat_message_media_attachments)
  end

  def render_messages(messages)
    render json: MisskeyCompat::ChatSerializer.messages(preload_messages(messages), viewer: current_account)
  end

  def render_invitations(invitations)
    render json: paginate(invitations).includes(:invitee_account, :inviter_account, chat_conversation: ROOM_PRELOADS).map { |invitation| MisskeyCompat::ChatSerializer.invitation(invitation, viewer: current_account) }
  end

  def serialize_message(message)
    MisskeyCompat::ChatSerializer.message(message, viewer: current_account)
  end

  def serialize_room(conversation)
    MisskeyCompat::ChatSerializer.room(conversation, viewer: current_account)
  end

  def serialize_membership(membership)
    MisskeyCompat::ChatSerializer.membership(membership, viewer: current_account)
  end

  def read_message?(message)
    message.account_id == current_account.id || message.chat_conversation.memberships.find { |membership| membership.account_id == current_account.id }&.last_read_message_id.to_i >= message.id
  end

  def with_media_ids
    return refuse('TOO_MANY_FILES', message: "A message can have up to #{Setting.chat_max_attachments} files.") if requested_file_ids.size > Setting.chat_max_attachments

    MisskeyCompat::DriveFileResolver.new.with_resolved(account: current_account, file_ids: requested_file_ids.presence, allow_drive_files: Setting.drive_enabled) do |media_ids|
      yield Array(media_ids)
    end
  end

  def requested_file_ids
    [*params[:fileId], *params[:fileIds]].uniq
  end

  def valid_message_text?(editing: false)
    return true if params[:text].present? && params[:text].strip.present?
    return true if !editing && requested_file_ids.present?

    refuse(editing ? 'INVALID_TEXT' : 'CONTENT_REQUIRED')
    false
  end

  def normalized_reaction
    params[:reaction].sub(/@\.:\z/, ':')
  end

  def refuse(code, message: nil)
    render_error(message || MisskeyCompat::ChatErrors.message(action_name, code), code, 400, id: MisskeyCompat::ChatErrors.id(action_name, code))
  end

  def render_not_found(error)
    refuse(
      case error.model
      when 'Account' then 'NO_SUCH_USER'
      when 'ChatMessage' then 'NO_SUCH_MESSAGE'
      when 'ChatInvitation' then action_name == 'cancel_invitation' ? 'NO_SUCH_INVITATION' : 'NO_SUCH_ROOM'
      else 'NO_SUCH_ROOM'
      end
    )
  end

  def render_chat_error(error)
    code = MisskeyCompat::ChatErrors::SERVICE_ERROR_CODES[error.message]
    return refuse(code) if code

    code = MisskeyCompat::ChatErrors.closest_code(action_name, error.message)
    return refuse(code, message: error.message) if code

    render_error(error.message, 'INVALID_PARAM', 400)
  end

  # CherryPick does not tell someone refused like this that there is anything there to be refused from.
  def render_chat_forbidden
    refuse(
      case action_name
      when *MESSAGE_ACTIONS then 'NO_SUCH_MESSAGE'
      when 'create_to_user' then Account.find(params[:toUserId]).blocking_or_domain_blocking?(current_account) ? 'YOU_HAVE_BEEN_BLOCKED' : 'CANNOT_CHAT_WITH_USER'
      when 'create_invitation' then invitation_refusal_code
      when 'cancel_invitation' then 'NO_SUCH_INVITATION'
      else 'NO_SUCH_ROOM'
      end
    )
  end

  def invitation_refusal_code
    invitee = Account.find(params[:userId])
    return 'YOU_HAVE_BEEN_BLOCKED' if invitee.blocking_or_domain_blocking?(current_account)
    return 'YOU_ARE_BLOCKING' if current_account.blocking_or_domain_blocking?(invitee)

    'CANNOT_CHAT_WITH_USER'
  end
end
