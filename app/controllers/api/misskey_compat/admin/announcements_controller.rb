# frozen_string_literal: true

class Api::MisskeyCompat::Admin::AnnouncementsController < Api::MisskeyCompat::Admin::ServerBaseController
  NO_SUCH_ANNOUNCEMENT_IDS = {
    'update' => 'd3aae5a7-6372-4cb4-b61c-f511ffc2d7cc',
    'destroy' => 'ecad8040-a276-4e85-bda9-015a708d291e',
  }.freeze
  STATUSES = %w(all active archived).freeze

  misskey_admin_endpoint :index, kind: 'read:admin:announcements', permission: :manage_announcements
  misskey_admin_endpoint :create, :update, :destroy, kind: 'write:admin:announcements', permission: :manage_announcements

  before_action :set_announcement, only: [:update, :destroy]

  def index
    status = params[:status].nil? ? 'active' : params[:status]
    return render_invalid_param('#/properties/status', 'must be one of all, active, archived') unless STATUSES.include?(status)
    return render json: [] if params[:userId].present?

    scope = BoardAnnouncement.all
    scope = scope.published if status == 'active'
    scope = scope.archived if status == 'archived'
    announcements = paginate_admin_scope(scope).includes(:attachments).to_a
    reads = BoardAnnouncementRead.where(board_announcement_id: announcements.map(&:id)).group(:board_announcement_id).count

    render json: announcements.map { |announcement| serialize_admin(announcement, reads.fetch(announcement.id, 0)) }
  end

  def create
    authorize :board_announcement, :create?
    return unless valid_announcement_params?(create: true)
    return render_invalid_param('#/properties/userId', 'user-specific announcements are not supported on this server') if params[:userId].present?

    announcement = BoardAnnouncement.new(account: current_account, published: true, **announcement_attributes(defaults: true))
    image = download_image(params[:imageUrl])
    return if performed?

    BoardAnnouncement.transaction do
      announcement.save!
      attach_image!(announcement, image)
    end
    log_action :create, announcement

    render json: MisskeyCompat::AnnouncementSerializer.serialize(announcement.reload)
  end

  def update
    authorize @announcement, :update?
    return unless valid_announcement_params?(create: false) && require_boolean_param!(:isActive)

    attributes = announcement_attributes(defaults: false)
    attributes[:published] = params[:isActive] if params.key?(:isActive)
    image_url = params[:imageUrl].presence
    keep_image = image_url.present? && image_url == current_image_url(@announcement)
    image = keep_image ? nil : download_image(image_url)
    return if performed?

    BoardAnnouncement.transaction do
      @announcement.update_with_archive_state(attributes, raise_error: true, republish_expired: true)
      attach_image!(@announcement, image) unless keep_image
    end
    log_action :update, @announcement

    head 204
  end

  def destroy
    authorize @announcement, :destroy?

    @announcement.destroy!
    log_action :destroy, @announcement

    head 204
  end

  private

  def set_announcement
    id = mi_id_param(:id)
    @announcement = BoardAnnouncement.find_by(id: id) if id.present?
    render_error('No such announcement', 'NO_SUCH_ANNOUNCEMENT', 404, id: NO_SUCH_ANNOUNCEMENT_IDS.fetch(action_name)) if @announcement.nil?
  end

  def valid_announcement_params?(create:)
    return false unless valid_auto_archive_at?(create: create)
    return false if create && !require_keys!(:title, :text, :imageUrl)
    return false unless %i(title text).all? { |key| !params.key?(key) || require_string_param!(key, min_length: 1) }
    return false if params.key?(:imageUrl) && !require_string_param!(:imageUrl, nullable: true)
    return false unless valid_enum?(:icon, BoardAnnouncement::ICONS) && valid_enum?(:display, BoardAnnouncement::DISPLAYS)

    %i(forExistingUsers silence needConfirmationToRead).all? { |key| require_boolean_param!(key) }
  end

  def valid_auto_archive_at?(create:)
    value = params[:autoArchiveAt]
    return true if value.nil?
    return render_invalid_param('#/properties/autoArchiveAt', 'must be an integer or null') && false unless value.is_a?(Integer)
    return true if value.between?(0, 8_640_000_000_000_000) && (!create || value > (Time.current.to_f * 1000).floor)

    id = create ? '2a892bd5-487d-46a2-a5fe-3d85ad51defe' : '01b83d7b-2fd5-4d7c-86c4-d03144d16355'
    render_error('Invalid auto archive date.', 'INVALID_AUTO_ARCHIVE_AT', 400, id: id) # rubocop:disable I18n/RailsI18n/DecorateString
    false
  end

  def valid_enum?(key, values)
    return true unless params.key?(key)
    return true if values.include?(params[key])

    reason = params[key] == 'dialog' ? 'dialog display is not supported on this server' : "must be one of #{values.join(', ')}"
    render_invalid_param("#/properties/#{key}", reason)
    false
  end

  def announcement_attributes(defaults:)
    attributes = {
      title: params[:title],
      text: params[:text],
      icon: params[:icon],
      display: params[:display],
      for_existing_users: params[:forExistingUsers],
      silence: params[:silence],
      need_confirmation_to_read: params[:needConfirmationToRead],
    }.compact
    attributes[:auto_archive_at] = params[:autoArchiveAt].nil? ? nil : Time.at(Rational(params[:autoArchiveAt], 1000)).utc if params.key?(:autoArchiveAt)
    return attributes unless defaults

    { icon: 'info', display: 'normal', for_existing_users: false, silence: false, need_confirmation_to_read: false }.merge(attributes)
  end

  def current_image_url(announcement)
    MisskeyCompat::AnnouncementSerializer.serialize(announcement)[:imageUrl]
  end

  def download_image(url)
    return nil if url.blank?

    parsed = Addressable::URI.parse(url)
    return render_invalid_image unless %w(http https).include?(parsed.scheme) && parsed.host.present?

    attachment = BoardAnnouncementAttachment.new
    Request.new(:get, url).perform do |response|
      raise Mastodon::UnexpectedResponseError, response unless (200...300).cover?(response.code)

      attachment.file = ResponseWithLimit.new(response, BoardAnnouncementAttachment::IMAGE_LIMIT)
    end
    return render_invalid_image unless attachment.valid? && attachment.image_content_type?

    attachment
  rescue Addressable::URI::InvalidURIError, Mastodon::UnexpectedResponseError, Mastodon::HostValidationError, Mastodon::LengthValidationError, Paperclip::Error, *Mastodon::HTTP_CONNECTION_ERRORS
    render_invalid_image
  end

  def render_invalid_image
    render_invalid_param('#/properties/imageUrl', 'must be a reachable image URL')
    nil
  end

  def attach_image!(announcement, image)
    announcement.attachments.select(&:image?).each(&:destroy!)
    return if image.nil?

    image.board_announcement = announcement
    image.save!
  end

  def serialize_admin(announcement, reads)
    {
      id: MisskeyCompat::MiId.encode(announcement.id),
      createdAt: announcement.created_at.iso8601,
      updatedAt: announcement.updated_at&.iso8601,
      title: announcement.title,
      text: announcement.text,
      imageUrl: current_image_url(announcement),
      icon: announcement.icon,
      display: announcement.display,
      isActive: announcement.active?,
      autoArchiveAt: announcement.auto_archive_at&.iso8601(3),
      forExistingUsers: announcement.for_existing_users,
      silence: announcement.silence,
      needConfirmationToRead: announcement.need_confirmation_to_read,
      userId: nil,
      reads: reads,
    }
  end
end
