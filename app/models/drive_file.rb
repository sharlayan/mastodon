# frozen_string_literal: true

# == Schema Information
#
# Table name: drive_files
#
#  id                               :bigint(8)        not null, primary key
#  blurhash                         :string
#  description                      :text
#  file_content_type                :string
#  file_file_name                   :string
#  file_file_size                   :integer
#  file_meta                        :json
#  file_storage_schema_version      :integer
#  file_updated_at                  :datetime
#  md5                              :string
#  sensitive                        :boolean          default(FALSE), not null
#  sha256                           :string
#  storage_file_size                :bigint(8)        default(0), not null
#  thumbnail_content_type           :string
#  thumbnail_file_name              :string
#  thumbnail_file_size              :integer
#  thumbnail_storage_schema_version :integer
#  thumbnail_updated_at             :datetime
#  type                             :integer          default("image"), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  account_id                       :bigint(8)        not null
#  folder_id                        :bigint(8)
#

class DriveFile < ApplicationRecord
  self.inheritance_column = nil

  include Attachmentable
  include Paginable

  enum :type, { image: 0, gifv: 1, video: 2, unknown: 3, audio: 4 }

  MAX_DESCRIPTION_LENGTH = MediaAttachment::MAX_DESCRIPTION_LENGTH

  EXTENSION_PATTERN = /\A[a-z0-9]{1,10}\z/

  IMAGE_WEBP_STYLES = {
    original: {
      format: 'webp',
      content_type: 'image/webp',
    }.merge(MediaAttachment::IMAGE_STYLES[:original]).freeze,

    small: {
      format: 'webp',
    }.merge(MediaAttachment::IMAGE_STYLES[:small]).freeze,
  }.freeze

  FORBIDDEN_EXTENSIONS = %w(
    asp aspx bash bat cgi cmd com css dll exe hta htm html jar js jsp lnk
    mjs msi phar php php3 php4 php5 phtml pl ps1 py reg rb scr sh svg swf
    vbs wasm xhtml xml xsl
  ).freeze

  FORBIDDEN_CONTENT_TYPES = %w(
    application/javascript application/x-javascript application/xhtml+xml
    application/xml image/svg+xml text/css text/html text/javascript text/xml
  ).freeze

  belongs_to :account
  belongs_to :folder, class_name: 'DriveFolder', optional: true
  has_one :custom_name, class_name: 'DriveFileName', inverse_of: :drive_file, autosave: true, dependent: :destroy
  has_many :media_attachments, inverse_of: :drive_file, dependent: :destroy

  has_attached_file :file,
                    styles: ->(f) { file_styles f },
                    processors: ->(f) { file_processors f },
                    convert_options: MediaAttachment::GLOBAL_CONVERT_OPTIONS

  before_file_validate :set_type_and_extension
  before_file_validate :check_video_dimensions

  validates_attachment_size :file, less_than: ->(m) { m.file_size_limit }

  has_attached_file :thumbnail,
                    styles: MediaAttachment::THUMBNAIL_STYLES,
                    processors: [:lazy_thumbnail, :blurhash_transcoder, :color_extractor],
                    convert_options: MediaAttachment::GLOBAL_CONVERT_OPTIONS

  validates_attachment_content_type :thumbnail, content_type: MediaAttachment::IMAGE_MIME_TYPES
  validates_attachment_size :thumbnail, less_than: MediaAttachment::IMAGE_LIMIT

  validates :file, presence: true
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validate :validate_content_type
  validate :validate_folder_ownership

  scope :ordered, -> { order(id: :desc) }

  scope :orphaned, lambda {
    where.not(id: MediaAttachment.in_use.where.not(drive_file_id: nil).select(:drive_file_id))
  }

  before_destroy :prevent_destroy_if_attached, prepend: true

  after_post_process :set_meta

  def display_name
    return file_file_name if custom_name.nil? || custom_name.marked_for_destruction?

    custom_name.name.presence || file_file_name
  end

  def display_name=(value)
    name = value.to_s.gsub(/[[:cntrl:]]/, ' ').squish.slice(0, DriveFileName::MAX_NAME_LENGTH)

    if name.blank?
      custom_name&.mark_for_destruction
    elsif custom_name.present?
      custom_name.name = name
    else
      build_custom_name(name: name)
    end
  end

  def larger_media_format?
    video? || gifv? || audio?
  end

  def file_size_limit
    configured = Setting.drive_max_file_size.to_i.megabytes
    media_limit = larger_media_format? ? MediaAttachment::VIDEO_LIMIT : MediaAttachment::IMAGE_LIMIT

    return media_limit unless configured.positive?
    return configured if unknown?

    [configured, media_limit].min
  end

  def audio_or_video?
    audio? || video?
  end

  def attached?
    media_attachments.in_use.exists?
  end

  def preview_available?
    file.styles.key?(:small) || thumbnail.present?
  end

  def preview_content_type
    return thumbnail_content_type if !file.styles.key?(:small) && thumbnail.present?

    style = file.styles[:small]
    style[:content_type].presence || Rack::Mime.mime_type(".#{style[:format]}", file_content_type)
  end

  def build_pointer(account)
    account.media_attachments.new(
      drive_file: self,
      type: self[:type],
      file_content_type: file_content_type,
      file_file_name: file_file_name,
      file_file_size: file_file_size,
      file_meta: file_meta,
      thumbnail_content_type: thumbnail_content_type,
      thumbnail_file_name: thumbnail_file_name,
      thumbnail_file_size: thumbnail_file_size,
      blurhash: blurhash,
      description: description,
      processing: :complete
    )
  end

  def quota_storage_file_size
    queued_files = [file, thumbnail].flat_map { |attachment| attachment.queued_for_write.values }
    queued_files.present? ? queued_files.sum(&:size) : storage_file_size
  end

  class << self
    def allowed_content_types
      MediaAttachment.supported_mime_types + extra_content_types
    end

    def extra_content_types
      extra_extensions.flat_map { |extension| MIME::Types.type_for("file.#{extension}").map(&:to_s) }.uniq - FORBIDDEN_CONTENT_TYPES
    end

    def extra_extensions
      parse_extensions(Setting.drive_allowed_extensions).grep(EXTENSION_PATTERN) - FORBIDDEN_EXTENSIONS
    end

    def parse_extensions(value)
      value.to_s.downcase.split(/[^a-z0-9]+/).compact_blank.uniq
    end

    def lock_for_media_attachments(media_attachments)
      ids = Array(media_attachments).filter_map(&:drive_file_id).uniq
      where(id: ids).order(:id).lock.load
    end

    def combined_media_file_size
      arel_table.coalesce(arel_table[:file_file_size], 0) + arel_table.coalesce(arel_table[:thumbnail_file_size], 0)
    end

    def max_download_size
      configured = Setting.drive_max_file_size.to_i.megabytes
      return MediaAttachment::VIDEO_LIMIT unless configured.positive?

      [configured, MediaAttachment::VIDEO_LIMIT].min
    end

    private

    def file_styles(attachment)
      content_type = attachment.instance.file_content_type

      if content_type == 'image/gif' || MediaAttachment::VIDEO_CONVERTIBLE_MIME_TYPES.include?(content_type)
        MediaAttachment::VIDEO_CONVERTED_STYLES
      elsif MediaAttachment::IMAGE_MIME_TYPES.include?(content_type) || MediaAttachment::IMAGE_CONVERTIBLE_MIME_TYPES.include?(content_type)
        if content_type == 'image/webp' || compress_to_webp?(attachment)
          IMAGE_WEBP_STYLES
        elsif MediaAttachment::IMAGE_CONVERTIBLE_MIME_TYPES.include?(content_type)
          MediaAttachment::IMAGE_CONVERTED_STYLES
        else
          MediaAttachment::IMAGE_STYLES
        end
      elsif MediaAttachment::VIDEO_MIME_TYPES.include?(content_type)
        MediaAttachment::VIDEO_STYLES
      elsif MediaAttachment::AUDIO_MIME_TYPES.include?(content_type)
        MediaAttachment::AUDIO_STYLES
      else
        {}
      end
    end

    def compress_to_webp?(attachment)
      return false unless attachment.queued_for_write.key?(:original)

      user = attachment.instance.account&.user
      user.present? && user.settings[:drive_upload_original_image] == false
    end

    def file_processors(instance)
      if instance.file_content_type == 'image/gif'
        [:gif_transcoder, :blurhash_transcoder]
      elsif MediaAttachment::VIDEO_MIME_TYPES.include?(instance.file_content_type)
        [:transcoder, :blurhash_transcoder, :type_corrector]
      elsif MediaAttachment::AUDIO_MIME_TYPES.include?(instance.file_content_type)
        [:image_extractor, :transcoder, :type_corrector]
      elsif MediaAttachment::IMAGE_MIME_TYPES.include?(instance.file_content_type)
        [:lazy_thumbnail, :blurhash_transcoder, :type_corrector]
      else
        []
      end
    end
  end

  private

  def prevent_destroy_if_attached
    lock!
    return unless attached?

    errors.add(:base, :restrict_dependent_destroy, record: MediaAttachment.model_name.human)
    throw :abort
  end

  def validate_folder_ownership
    return if folder_id.blank?

    errors.add(:folder_id, :invalid) if folder.nil? || folder.account_id != account_id
  end

  def set_type_and_extension
    self.type = begin
      if MediaAttachment::VIDEO_MIME_TYPES.include?(file_content_type)
        :video
      elsif MediaAttachment::AUDIO_MIME_TYPES.include?(file_content_type)
        :audio
      elsif MediaAttachment::IMAGE_MIME_TYPES.include?(file_content_type)
        :image
      else
        :unknown
      end
    end
  end

  def validate_content_type
    return if file_content_type.blank?

    errors.add(:file, :invalid) unless self.class.allowed_content_types.include?(file_content_type)
  end

  def set_meta
    meta = populate_meta
    file.instance_write :meta, meta
    self.storage_file_size = quota_storage_file_size
  end

  def populate_meta
    meta = (file.instance_read(:meta) || {}).with_indifferent_access.slice(*MediaAttachment::META_KEYS)

    file.queued_for_write.each do |style, local_file|
      meta[style] = if style == :small || image?
                      image_geometry(local_file)
                    elsif audio_or_video? || gifv?
                      video_metadata(local_file)
                    else
                      {}
                    end
    end

    meta[:small] = image_geometry(thumbnail.queued_for_write[:original]) if thumbnail.queued_for_write.key?(:original)

    meta
  end

  def image_geometry(local_file)
    width, height = FastImage.size(local_file.path)

    return {} if width.nil?

    {
      width: width,
      height: height,
      size: "#{width}x#{height}",
      aspect: width.to_f / height,
    }
  end

  def video_metadata(local_file)
    movie = VideoMetadataExtractor.new(local_file.path)

    return {} unless movie.valid?

    {
      width: movie.width,
      height: movie.height,
      frame_rate: movie.frame_rate,
      duration: movie.duration,
      bitrate: movie.bitrate,
    }.compact
  end
end
