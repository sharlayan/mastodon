# frozen_string_literal: true

# == Schema Information
#
# Table name: custom_emojis
#
#  id                           :bigint(8)        not null, primary key
#  aliases                      :text             default([]), not null, is an Array
#  disabled                     :boolean          default(FALSE), not null
#  domain                       :string
#  image_content_type           :string
#  image_file_name              :string
#  image_file_size              :integer
#  image_remote_url             :string
#  image_storage_schema_version :integer
#  image_updated_at             :datetime
#  is_sensitive                 :boolean          default(FALSE), not null
#  license                      :text
#  local_only                   :boolean          default(FALSE), not null
#  shortcode                    :string           default(""), not null
#  uri                          :string
#  visible_in_picker            :boolean          default(TRUE), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  category_id                  :bigint(8)
#

class CustomEmoji < ApplicationRecord
  include Attachmentable
  include Sharlayan::CustomEmojiExtensions

  LOCAL_LIMIT = Sharlayan::CustomEmojiExtensions::LOCAL_LIMIT
  LIMIT = Sharlayan::CustomEmojiExtensions::LIMIT
  SHORTCODE_RE_FRAGMENT = Sharlayan::CustomEmojiExtensions::SHORTCODE_RE_FRAGMENT
  SCAN_RE = Sharlayan::CustomEmojiExtensions::SCAN_RE
  UNBOUNDED_SCAN_RE = Sharlayan::CustomEmojiExtensions::UNBOUNDED_SCAN_RE
  SHORTCODE_ONLY_RE = Sharlayan::CustomEmojiExtensions::SHORTCODE_ONLY_RE
  IMAGE_MIME_TYPES = Sharlayan::CustomEmojiExtensions::IMAGE_MIME_TYPES

  belongs_to :category, class_name: 'CustomEmojiCategory', optional: true

  has_one :local_counterpart, -> { where(domain: nil) }, class_name: 'CustomEmoji', primary_key: :shortcode, foreign_key: :shortcode, inverse_of: false, dependent: nil

  has_attached_file :image, styles: { static: { format: 'png', convert_options: '-coalesce +profile "!icc,*" +set date:modify +set date:create +set date:timestamp', file_geometry_parser: FastGeometryParser } }, validate_media_type: false, processors: [:lazy_thumbnail]

  normalizes :domain, with: ->(domain) { domain.downcase.strip }

  validates_attachment :image, content_type: { content_type: IMAGE_MIME_TYPES }, presence: true
  validates_attachment_size :image, less_than: LIMIT, unless: :local?
  validates_attachment_size :image, less_than: LOCAL_LIMIT, if: :local?
  validates :shortcode, uniqueness: { scope: :domain }, format: { with: SHORTCODE_ONLY_RE }, length: { minimum: 1 }

  scope :local, -> { where(domain: nil) }
  scope :remote, -> { where.not(domain: nil) }
  scope :enabled, -> { where(disabled: false) }
  scope :alphabetic, -> { order(domain: :asc, shortcode: :asc) }
  scope :by_domain_and_subdomains, ->(domain) { where(domain: domain).or(where(arel_table[:domain].matches("%.#{domain}"))) }
  scope :listed, -> { local.enabled.where(visible_in_picker: true) }

  remotable_attachment :image, LIMIT

  after_commit :remove_entity_cache

  def local?
    domain.nil?
  end

  def object_type
    :emoji
  end

  def featured?
    category&.featured_emoji_id == id
  end

  def copy!
    copy = self.class.find_or_initialize_by(domain: nil, shortcode: shortcode)
    copy.image = image
    copy.tap(&:save!)
  end

  def to_log_human_identifier
    shortcode
  end

  class << self
    def from_text(text, domain = nil, allow_unbounded_shortcodes: false)
      return [] if text.blank?

      pattern = allow_unbounded_shortcodes ? UNBOUNDED_SCAN_RE : SCAN_RE
      shortcodes = text.scan(pattern).map(&:first).uniq

      return [] if shortcodes.empty?

      EntityCache.instance.emoji(shortcodes, domain)
    end
  end

  private

  def remove_entity_cache
    Rails.cache.delete(EntityCache.instance.to_key(:emoji, shortcode, domain))
  end
end
