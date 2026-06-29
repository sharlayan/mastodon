# frozen_string_literal: true

# == Schema Information
#
# Table name: board_announcement_attachments
#
#  id                    :bigint(8)        not null, primary key
#  blurhash              :string
#  file_content_type     :string
#  file_file_name        :string
#  file_file_size        :integer
#  file_meta             :json
#  file_updated_at       :datetime
#  type                  :integer          default("image"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  board_announcement_id :bigint(8)
#

class BoardAnnouncementAttachment < ApplicationRecord
  self.inheritance_column = nil

  include Attachmentable

  enum :type, { image: 0, file: 1 }

  IMAGE_LIMIT = (ENV['MAX_IMAGE_SIZE'] || 16.megabytes).to_i
  FILE_LIMIT = (ENV['MAX_FILE_SIZE'] || 99.megabytes).to_i

  IMAGE_CONTENT_TYPES = %w(image/jpeg image/png image/gif image/webp image/avif).freeze
  VIDEO_CONTENT_TYPES = %w(video/webm video/mp4 video/quicktime video/ogg).freeze
  AUDIO_CONTENT_TYPES = %w(audio/wave audio/wav audio/x-wav audio/x-pn-wave audio/vnd.wave audio/ogg audio/vorbis audio/mpeg audio/mp3 audio/webm audio/flac audio/aac audio/m4a audio/x-m4a audio/mp4 audio/3gpp video/x-ms-asf).freeze
  ARCHIVE_CONTENT_TYPES = %w(
    application/zip
    application/x-zip-compressed
    application/gzip
    application/x-gzip
    application/x-tar
    application/x-bzip
    application/x-bzip2
    application/x-7z-compressed
    application/vnd.rar
    application/x-rar-compressed
    application/x-xz
    application/zstd
    application/x-zstd
  ).freeze
  FILE_CONTENT_TYPES = (IMAGE_CONTENT_TYPES + VIDEO_CONTENT_TYPES + AUDIO_CONTENT_TYPES + ARCHIVE_CONTENT_TYPES).freeze

  IMAGE_STYLES = {
    original: {
      pixels: 2_073_600, # 1920x1080
      file_geometry_parser: FastGeometryParser,
    }.freeze,

    small: {
      pixels: 160_000, # 400x400
      file_geometry_parser: FastGeometryParser,
      blurhash: {
        x_comp: 4,
        y_comp: 4,
      }.freeze,
    }.freeze,
  }.freeze

  belongs_to :board_announcement, inverse_of: :attachments, optional: true

  has_attached_file :file,
                    styles: ->(f) { image_content_type?(f) ? IMAGE_STYLES : {} },
                    processors: ->(f) { image_content_type?(f) ? [:lazy_thumbnail, :blurhash_transcoder, :type_corrector] : [] },
                    convert_options: { all: '-quality 90 +profile "!icc,*" +set modify-date +set create-date' }

  validates_attachment_content_type :file, content_type: FILE_CONTENT_TYPES
  validates_attachment_size :file, less_than: ->(m) { m.image_content_type? ? IMAGE_LIMIT : FILE_LIMIT }
  validates :file, presence: true

  before_validation :set_type

  def self.image_content_type?(attachment_or_record)
    record = attachment_or_record.respond_to?(:instance) ? attachment_or_record.instance : attachment_or_record

    record.image_content_type?
  end

  def to_param
    id.to_s
  end

  def image_content_type?
    IMAGE_CONTENT_TYPES.include?(file_content_type.presence || file.content_type)
  end

  private

  def set_type
    return if file.content_type.blank?

    self.type = image_content_type? ? :image : :file
  end
end
