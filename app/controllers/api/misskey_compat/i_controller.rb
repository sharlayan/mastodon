# frozen_string_literal: true

class Api::MisskeyCompat::IController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  def show
    render json: me_json
  end

  def update
    return unless object_body!

    apply_profile!
    apply_privacy!
    apply_muted_words!
    apply_muted_instances!
    apply_muted_emojis!

    render json: me_json
  end

  def read_announcement
    announcement = BoardAnnouncement.published.find_by(id: params[:announcementId])
    return render_error('No such announcement', 'NO_SUCH_ANNOUNCEMENT', 404) if announcement.nil?

    BoardAnnouncementRead.find_or_create_by(account: current_account, board_announcement: announcement)
    head 204
  end

  def pin
    status = pinnable_status
    return if performed?

    StatusPin.create!(account: current_account, status: status)
    distribute_pin_activity!(status, ActivityPub::AddNoteSerializer)
    render json: me_json
  rescue ActiveRecord::RecordInvalid
    render_error('You can not pin this note', 'CANNOT_PIN', 400)
  end

  def unpin
    status = pinnable_status
    return if performed?

    pin = StatusPin.find_by(account: current_account, status: status)
    if pin
      pin.destroy!
      distribute_pin_activity!(status, ActivityPub::RemoveNoteSerializer)
    end
    render json: me_json
  end

  private

  def pinnable_status
    status = Status.find_by(id: params[:noteId])
    render_error('No such note', 'NO_SUCH_NOTE', 404) and return if status.nil? || status.account_id != current_account.id

    status
  end

  def distribute_pin_activity!(status, serializer)
    json = ActiveModelSerializers::SerializableResource.new(status, serializer: serializer, adapter: ActivityPub::Adapter).as_json
    ActivityPub::RawDistributionWorker.perform_async(json.to_json, current_account.id)
  end

  def me_json
    data = MisskeyCompat::UserSerializer.serialize(current_account, detailed: true, me_user: current_user)
    data[:hasUnreadAnnouncement] = unread_announcement?
    data[:policies] = compat_policies
    data
  end

  def apply_profile!
    attrs = {}
    attrs[:display_name] = params[:name].to_s if params.key?(:name)
    attrs[:note] = params[:description].to_s if params.key?(:description)
    attrs[:followed_message] = params[:followedMessage].to_s.presence if params.key?(:followedMessage)
    attrs[:location] = params[:location].to_s.presence if params.key?(:location)
    attrs[:birthday] = params[:birthday].to_s.presence if params.key?(:birthday)
    attrs[:locked] = boolean_param(params[:isLocked]) if params.key?(:isLocked)
    attrs[:discoverable] = boolean_param(params[:isExplorable]) if params.key?(:isExplorable)
    attrs[:actor_type] = boolean_param(params[:isBot]) ? 'Service' : 'Person' if params.key?(:isBot)
    attrs[:fields_attributes] = fields_attributes if params.key?(:fields)
    attrs[:avatar_decorations] = avatar_decorations_attributes if params.key?(:avatarDecorations)

    hide = ff_hide_collections
    attrs[:hide_collections] = hide unless hide.nil?

    avatar = drive_file(params[:avatarId]) if params.key?(:avatarId)
    header = drive_file(params[:bannerId]) if params.key?(:bannerId)
    attrs[:avatar] = avatar.file if avatar
    attrs[:header] = header.file if header

    UpdateAccountService.new.call(current_account, attrs, raise_error: true) if attrs.present?
  end

  def apply_privacy!
    settings = {}
    settings['noindex'] = boolean_param(params[:noCrawle]) if params.key?(:noCrawle)
    settings['default_sensitive'] = boolean_param(params[:alwaysMarkNsfw]) if params.key?(:alwaysMarkNsfw)
    settings['auto_accept_followed'] = boolean_param(params[:autoAcceptFollowed]) if params.key?(:autoAcceptFollowed)
    settings['show_reactions'] = boolean_param(params[:publicReactions]) if params.key?(:publicReactions)
    settings['hide_online_status'] = boolean_param(params[:hideOnlineStatus]) if params.key?(:hideOnlineStatus)
    settings['prevent_ai_learning'] = boolean_param(params[:preventAiLearning]) if params.key?(:preventAiLearning)
    settings['default_language'] = params[:lang].to_s.presence if params.key?(:lang)

    current_user.update!(settings_attributes: settings) if settings.present?
  end

  def fields_attributes
    Array(params[:fields]).first(4).map do |field|
      { name: field[:name].to_s, value: field[:value].to_s }
    end
  end

  def avatar_decorations_attributes
    Array(params[:avatarDecorations]).map do |config|
      {
        id: MisskeyCompat::MiId.decode(config[:id]),
        angle: config[:angle],
        flip_h: config[:flipH],
        offset_x: config[:offsetX],
        offset_y: config[:offsetY],
        scale: config.key?(:scale) ? config[:scale] : 1.0,
        opacity: config.key?(:opacity) ? config[:opacity] : 1.0,
      }
    end
  end

  def ff_hide_collections
    visibility = params[:followingVisibility] || params[:followersVisibility] || params[:ffVisibility]
    return nil if visibility.nil?

    visibility.to_s != 'public'
  end

  def drive_file(id)
    return nil if id.blank?

    current_account.media_attachments.find_by(id: id)
  end

  def boolean_param(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def apply_muted_words!
    apply_muted_word_setting!('misskey_muted_words', params[:mutedWords])
    apply_muted_word_setting!('misskey_hard_muted_words', params[:hardMutedWords])
  end

  def apply_muted_word_setting!(key, value)
    return if value.nil?

    raise ArgumentError, "#{key} must be an array" unless value.is_a?(Array)

    current_user.update!(settings_attributes: { key => JSON.generate(value) })
  end

  def apply_muted_instances!
    return if params[:mutedInstances].nil?

    raise ArgumentError, 'mutedInstances must be an array' unless params[:mutedInstances].is_a?(Array)

    desired = params[:mutedInstances].filter_map { |host| host.to_s.downcase.strip.presence }.uniq
    existing = current_account.domain_mutes.pluck(:domain)

    (existing - desired).each { |domain| current_account.unmute_domain!(domain) }
    (desired - existing).each do |domain|
      current_account.mute_domain!(domain)
    rescue ActiveRecord::RecordInvalid
      next
    end
  end

  def apply_muted_emojis!
    return if params[:mutedEmojis].nil?

    raise ArgumentError, 'mutedEmojis must be an array' unless params[:mutedEmojis].is_a?(Array)

    MisskeyCompat::MutedEmojiConverter.apply(current_account, params[:mutedEmojis])
  end

  def unread_announcement?
    BoardAnnouncement.published
      .for_account(current_account)
      .where(silence: false)
      .where.not(id: BoardAnnouncementRead.where(account: current_account).select(:board_announcement_id))
      .exists?
  end
end
