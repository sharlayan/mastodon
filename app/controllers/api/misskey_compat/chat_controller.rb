# frozen_string_literal: true

class Api::MisskeyCompat::ChatController < Api::MisskeyCompat::BaseController
  READ_ACTIONS = %i(history user_timeline room_timeline show search owned_rooms joining_rooms room_members show_room invitations_inbox invitations_outbox).freeze
  WRITE_ACTIONS = %i(read_all create_to_user create_to_room update destroy react unreact create_room update_room destroy_room mute_room leave_room kick_member join_room create_invitation ignore_invitation reject_invitation cancel_invitation).freeze
  BOOLEAN_VALUES = [true, false].freeze
  NULLABLE_SEARCH_IDS = %i(userId roomId).freeze
  CREATE_MESSAGE_ACTIONS = %w(create_to_user create_to_room).freeze
  NONEMPTY_FIELDS = %i(name query reaction).freeze
  CHAT_ID_PARAMS = %i(messageId roomId toRoomId toUserId invitationId).freeze
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
  rescue_from Sharlayan::ChatService::Forbidden do
    render_error('You are not allowed to access this chat', 'PERMISSION_DENIED', 403)
  end
  rescue_from MisskeyCompat::DriveFileResolver::NoSuchFileError do
    render_error('No such file', 'NO_SUCH_FILE', 400)
  end
  rescue_from MisskeyCompat::DriveFileResolver::AmbiguousFileError do
    render_invalid_param('#/properties/fileId', 'ambiguous file id')
  end

  def history
    conversations = accessible_conversations.where(conversation_type: params[:room] ? :group : :direct)
    latest_ids = ChatMessage.visible.visible_to(current_account).where(chat_conversation_id: conversations.select(:id)).group(:chat_conversation_id).select('MAX(chat_messages.id)')
    messages = ChatMessage.where(id: latest_ids).order(id: :desc).limit(pagination_limit(default: 10, max: 100))
    render json: preload_messages(messages).map { |message| serialize_message(message).merge(isRead: read_message?(message)) }
  end

  def read_all
    accessible_conversations.find_each { |conversation| chat_service.mark_read(current_account, conversation) }
    head 204
  end

  def user_timeline
    other = find_account!(:userId)
    conversation = direct_conversation_for(other.id)
    return render json: [] if conversation.nil?

    messages = paginate(conversation.messages.visible_to(current_account), default: 10)
    chat_service.mark_read(current_account, conversation)
    render_messages(messages)
  end

  def room_timeline
    conversation = member_room!
    messages = paginate(conversation.messages.visible_to(current_account), default: 10)
    chat_service.mark_read(current_account, conversation)
    render_messages(messages)
  end

  def show
    render json: serialize_message(find_message!)
  end

  def create_to_user
    recipient = find_account!(:toUserId)
    return render_error('Cannot send a message to yourself', 'RECIPIENT_IS_YOURSELF', 400) if recipient.id == current_account.id
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
    render json: paginate(rooms).map { |conversation| serialize_room(conversation) }
  end

  def joining_rooms
    memberships = ChatMembership.joins(:chat_conversation).where(account: current_account, chat_conversations: { conversation_type: :group }).where.not(role: :owner)
    render json: paginate(memberships).includes(:account, :chat_conversation).map { |membership| serialize_membership(membership) }
  end

  def room_members
    memberships = paginate(member_room!.memberships.where.not(role: :owner))
    render json: memberships.includes(:account, :chat_conversation).map { |membership| serialize_membership(membership) }
  end

  def show_room
    room = accessible_conversations.chat_group.find_by(id: params[:roomId])
    room ||= ChatConversation.chat_group.joins(:invitations).where(chat_invitations: { invitee_account_id: current_account.id, state: :pending }).find(params[:roomId])
    render json: serialize_room(room)
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
    return render_error('No such room', 'NO_SUCH_ROOM', 400) if room.nil?

    member = room.memberships.where.not(account_id: current_account.id).find_by(account_id: params[:userId])
    return render_error('No such member', 'NO_SUCH_MEMBER', 400) if member.nil?

    chat_service.kick(current_account, room, member.account)
    head 204
  end

  def invitations_inbox
    invitations = ChatInvitation.pending.from_available_inviters.where(invitee_account: current_account, ignored: false)
    render_invitations(invitations)
  end

  def invitations_outbox
    room = accessible_conversations.chat_group.where(owner_account: current_account).find(params[:roomId])
    render_invitations(room.invitations.pending)
  end

  def create_invitation
    invitation = chat_service.invite(current_account, member_room!, find_account!(:userId))
    render json: MisskeyCompat::ChatSerializer.invitation(invitation, viewer: current_account)
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

      return render_invalid_param("#/properties/#{key}", 'must be an id') unless chat_id?(params[key])
    end

    return render_invalid_param('#/properties/fileIds', 'must be a list of ids') if params.key?(:fileIds) && !(params[:fileIds].is_a?(Array) && params[:fileIds].all? { |id| chat_id?(id) })

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
    end
  end

  def chat_id?(value)
    value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
  end

  def enforce_write_rate_limit!
    rate_limited?(:chat_writes) unless current_user.can_extra?(:bypass_rate_limit)
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
    messages.includes(:account, chat_conversation: [:owner_account, :invitations, :memberships, :accounts], reactions: :account, media_attachments: :chat_message_media_attachments)
  end

  def render_messages(messages)
    render json: preload_messages(messages).map { |message| serialize_message(message) }
  end

  def render_invitations(invitations)
    render json: paginate(invitations).includes(:chat_conversation, :invitee_account, :inviter_account).map { |invitation| MisskeyCompat::ChatSerializer.invitation(invitation, viewer: current_account) }
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
    message.account_id == current_account.id || message.chat_conversation.memberships.find_by!(account: current_account).last_read_message_id.to_i >= message.id
  end

  def with_media_ids
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

    render_error('Message text is empty', 'INVALID_TEXT', 400)
    false
  end

  def normalized_reaction
    params[:reaction].sub(/@\.:\z/, ':')
  end

  def render_not_found(error)
    code = case error.model
           when 'Account' then 'NO_SUCH_USER'
           when 'ChatMessage' then 'NO_SUCH_MESSAGE'
           when 'ChatInvitation' then 'NO_SUCH_INVITATION'
           else 'NO_SUCH_ROOM'
           end
    render_error('No such resource', code, 404)
  end

  def render_chat_error(error)
    code = error.message == 'Archived conversations are read-only' ? 'ROOM_IS_ARCHIVED' : 'INVALID_PARAM'
    render_error(error.message, code, 400)
  end
end
