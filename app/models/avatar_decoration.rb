# frozen_string_literal: true

require 'request_store'

# == Schema Information
#
# Table name: avatar_decorations
#
#  id                 :bigint(8)        not null, primary key
#  approved           :boolean          default(FALSE), not null
#  description        :text             default("")
#  host               :string
#  image_content_type :string
#  image_file_name    :string
#  image_file_size    :integer
#  image_remote_url   :string
#  image_updated_at   :datetime
#  name               :string           default(""), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  category_id        :bigint(8)
#  remote_id          :string
#  required_role_id   :bigint(8)
#
class AvatarDecoration < ApplicationRecord
  include Attachmentable
  include Remotable

  IMAGE_MIME_TYPES = %w(image/png image/gif image/webp image/apng).freeze
  IMAGE_LIMIT = (ENV['MAX_AVATAR_DECORATION_SIZE'] || 5.megabytes).to_i

  belongs_to :required_role, class_name: 'UserRole', optional: true
  belongs_to :category, class_name: 'AvatarDecorationCategory', optional: true, inverse_of: :decorations

  attr_accessor :category_name

  scope :local,    -> { where(host: nil) }
  scope :remote,   -> { where.not(host: nil) }
  scope :approved, -> { where(approved: true) }
  scope :pending_approval, -> { where(approved: false) }
  MAX_REMOTE_DECORATIONS = 16

  scope :available_to_role, lambda { |role|
    where(required_role_id: nil)
      .or(where(required_role: UserRole.where(position: ..role.position)))
  }

  has_attached_file :image,
                    styles: { static: { format: :png, convert_options: '-coalesce +profile "!icc,*"' } },
                    validate_media_type: false,
                    processors: [:lazy_thumbnail]

  validates_attachment_content_type :image, content_type: IMAGE_MIME_TYPES
  validates_attachment_size :image, less_than: IMAGE_LIMIT
  remotable_attachment :image, IMAGE_LIMIT, download_on_assign: false

  validates :name, presence: true, length: { maximum: 256 }
  validates :description, length: { maximum: 2048 }
  validate :image_or_remote_url_present
  validates :remote_id, uniqueness: { scope: :host }, allow_nil: true

  def self.find_many_cached(ids)
    cache = RequestStore.store[:avatar_decorations_by_id] ||= {}
    missing_ids = ids.reject { |id| cache.key?(id) }
    if missing_ids.any?
      where(id: missing_ids).find_each { |d| cache[d.id] = d }
      missing_ids.each { |id| cache[id] ||= nil }
    end
    ids.filter_map { |id| cache[id] }
  end

  def local?
    host.nil?
  end

  def image_url
    if image_file_name.present?
      image.url(:original)
    else
      image_remote_url
    end
  end

  def image_stored?
    return false if image_file_name.blank?

    image.exists?(:original)
  rescue => e
    Rails.logger.warn "AvatarDecoration##{id}: storage check failed: #{e.message}"
    true
  end

  def image_missing?
    !image_stored?
  end

  def image_repairable?
    image_remote_url.present? && image_missing?
  end

  def repair_image!
    return false unless image_repairable?

    download_image!
    return false if image_file_name.blank?

    save
  end

  def image_static_url
    if image_file_name.present? && image_content_type == 'image/gif'
      image.url(:static)
    else
      image_url
    end
  end

  private

  def image_or_remote_url_present
    return if image_file_name.present? || image_remote_url.present?

    errors.add(:image, :blank)
  end
end
