# frozen_string_literal: true

# == Schema Information
#
# Table name: board_announcement_attachments
#
#  id                    :bigint(8)        not null, primary key
#  board_announcement_id :bigint(8)        not null
#  type                  :integer          default("image"), not null
#  file_file_name        :string
#  file_content_type     :string
#  file_file_size        :integer
#  file_updated_at       :datetime
#  blurhash              :string
#  file_meta             :json
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#

class BoardAnnouncementAttachment < ApplicationRecord
  self.inheritance_column = nil

  include Attachmentable

  enum :type, { image: 0, file: 1 }

  IMAGE_LIMIT = (ENV['MAX_IMAGE_SIZE'] || 16.megabytes).to_i
  FILE_LIMIT = (ENV['MAX_FILE_SIZE'] || 99.megabytes).to_i

  IMAGE_CONTENT_TYPES = %w(image/jpeg image/png image/gif image/webp image/avif).freeze

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
                    styles: ->(f) { f.instance.image? ? IMAGE_STYLES : {} },
                    processors: ->(f) { f.image? ? [:lazy_thumbnail, :blurhash_transcoder, :type_corrector] : [] },
                    convert_options: { all: '-quality 90 +profile "!icc,*" +set modify-date +set create-date' }

  validates_attachment_content_type :file, content_type: /\A.*\z/
  validates_attachment_size :file, less_than: ->(m) { m.image? ? IMAGE_LIMIT : FILE_LIMIT }
  validates :file, presence: true

  before_validation :set_type

  def to_param
    id.to_s
  end

  private

  def set_type
    return if file.content_type.blank?

    self.type = IMAGE_CONTENT_TYPES.include?(file.content_type) ? :image : :file
  end
end
