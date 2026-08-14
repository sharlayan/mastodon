# frozen_string_literal: true

# == Schema Information
#
# Table name: site_uploads
#
#  id                :bigint(8)        not null, primary key
#  blurhash          :string
#  file_content_type :string
#  file_file_name    :string
#  file_file_size    :integer
#  file_updated_at   :datetime
#  meta              :json
#  var               :string           default(""), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

class SiteUpload < ApplicationRecord
  include Attachmentable

  FAVICON_SIZES = [16, 32, 48].freeze
  APPLE_ICON_SIZES   = [57, 60, 72, 76, 114, 120, 144, 152, 167, 180, 1024].freeze
  ANDROID_ICON_SIZES = [36, 48, 72, 96, 144, 192, 256, 384, 512].freeze

  APP_ICON_SIZES = (APPLE_ICON_SIZES + ANDROID_ICON_SIZES).uniq.freeze

  STYLES = {
    app_icon:
      APP_ICON_SIZES.to_h do |size|
        [:"#{size}", { format: 'png', geometry: "#{size}x#{size}#", file_geometry_parser: FastGeometryParser }]
      end.freeze,

    favicon:
      FAVICON_SIZES.to_h do |size|
        [:"#{size}", { format: 'png', geometry: "#{size}x#{size}#", file_geometry_parser: FastGeometryParser }]
      end.freeze,

    thumbnail: {
      '@1x': {
        format: 'png',
        geometry: '1200x630#',
        file_geometry_parser: FastGeometryParser,
        blurhash: {
          x_comp: 4,
          y_comp: 4,
        }.freeze,
      },

      '@2x': {
        format: 'png',
        geometry: '2400x1260#',
        file_geometry_parser: FastGeometryParser,
      }.freeze,
    }.freeze,

    mascot: {}.freeze,
    background_image: {}.freeze,
    glitch_mascot1: {}.freeze,
    glitch_mascot2: {}.freeze,
    glitch_mascot3: {}.freeze,
    glitch_mascot4: {}.freeze,
  }.freeze

  has_attached_file :file, styles: ->(file) { styles_for(file) }, convert_options: { all: '-coalesce +profile "!icc,*" +set date:modify +set date:create +set date:timestamp' }, processors: [:lazy_thumbnail, :blurhash_transcoder, :type_corrector]

  validates_attachment_content_type :file, content_type: %r{\Aimage/.*\z}
  validates :file, presence: true
  validates :var, presence: true, uniqueness: true

  before_save :set_meta
  after_commit :clear_cache

  def cache_key
    "site_uploads/#{var}"
  end

  def self.styles_for(attachment)
    case attachment.instance.var.to_sym
    when :logo_icon
      logo_crop_style(attachment, 1, 1)
    when :logo_wordmark_dark, :logo_wordmark_light
      logo_crop_style(attachment, 261, 66)
    else
      STYLES[attachment.instance.var.to_sym]
    end
  end

  def self.logo_crop_style(attachment, ratio_width, ratio_height)
    width, height = attachment_dimensions(attachment)
    return {} unless width && height

    if width * ratio_height > height * ratio_width
      width = (height * ratio_width / ratio_height.to_f).floor
    else
      height = (width * ratio_height / ratio_width.to_f).floor
    end

    { original: { geometry: "#{width}x#{height}#", file_geometry_parser: FastGeometryParser } }
  end

  def self.attachment_dimensions(attachment)
    queued_file = attachment.queued_for_write[:original]
    return FastImage.size(queued_file.path) if queued_file

    attachment.instance.meta&.values_at('width', 'height')
  end

  private_class_method :styles_for, :logo_crop_style, :attachment_dimensions

  private

  def set_meta
    tempfile = file.queued_for_write[:original]

    return if tempfile.nil?

    width, height = FastImage.size(tempfile.path)
    self.meta = { width: width, height: height }
  end

  def clear_cache
    Rails.cache.delete(cache_key)
  end
end
