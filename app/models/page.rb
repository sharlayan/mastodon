# frozen_string_literal: true

# == Schema Information
#
# Table name: pages
#
#  id                               :bigint(8)        not null, primary key
#  access_password_digest           :string
#  align_center                     :boolean          default(FALSE), not null
#  category                         :string
#  content                          :jsonb            not null
#  draft                            :boolean          default(FALSE), not null
#  font                             :string           default("sans-serif"), not null
#  hide_title_when_pinned           :boolean          default(FALSE), not null
#  is_main                          :boolean          default(FALSE), not null
#  likes_count                      :integer          default(0), not null
#  name                             :string           not null
#  summary                          :text
#  title                            :string           default(""), not null
#  visibility                       :string           default("public"), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  account_id                       :bigint(8)        not null
#  eye_catching_media_attachment_id :bigint(8)
#

class Page < ApplicationRecord
  include Paginable

  class ContentLimitError < StandardError; end

  DEFAULT_PER_ACCOUNT_LIMIT = 500
  DEFAULT_DAILY_CREATE_LIMIT = 20
  LIST_LIMIT = 20
  MAX_LIST_LIMIT = 100
  TITLE_LENGTH_LIMIT = 256
  NAME_LENGTH_LIMIT = 256
  SUMMARY_LENGTH_LIMIT = 256
  CATEGORY_LENGTH_LIMIT = 30
  NAME_RE = %r{\A[^\s:/?#\[\]@!$&'()*+,;=\\%\x00-\x20]{1,256}\z}
  FONTS = %w(sans-serif serif).freeze
  VISIBILITIES = %w(public authenticated password private).freeze
  BLOCK_TYPES = %w(text section image note youtube).freeze
  MAX_BLOCKS = 500
  MAX_BLOCK_DEPTH = 10
  MAX_CONTENT_BYTES = 512.kilobytes
  MAX_TEXT_LENGTH = 20_000
  MAX_SECTION_TITLE_LENGTH = 100
  MAX_YOUTUBE_URL_LENGTH = 512
  YOUTUBE_VIDEO_ID_RE = /\A[\w-]{11}\z/
  YOUTUBE_SIZES = %w(small medium large).freeze
  BLOCK_TYPE_LIMITS = {
    'image' => 32,
    'note' => 20,
    'youtube' => 16,
  }.freeze

  belongs_to :account
  belongs_to :eye_catching_media_attachment, class_name: 'MediaAttachment', optional: true

  has_many :page_likes, inverse_of: :page, dependent: :destroy
  has_many :page_reports, dependent: :delete_all

  before_validation :normalize_category
  before_validation :synchronize_visibility
  before_validation :clear_unused_password
  before_validation :clear_main_unless_public

  validates :title, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :name, presence: true, length: { maximum: NAME_LENGTH_LIMIT }, format: { with: NAME_RE }, uniqueness: { scope: :account_id }
  validates :summary, length: { maximum: SUMMARY_LENGTH_LIMIT }
  validates :category, length: { maximum: CATEGORY_LENGTH_LIMIT }
  validates :font, inclusion: { in: FONTS }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :access_password, length: { in: Devise.password_length }, allow_nil: true
  validate :validate_content
  validate :validate_attached_media
  validate :validate_access_password
  validate :validate_eye_catching_media_attachment
  validate :validate_account_pages_limit, on: :create
  validate :validate_daily_create_limit, on: :create

  scope :available_accounts, -> { joins(:account).merge(Account.without_suspended) }
  scope :publicly_accessible, -> { available_accounts.where(visibility: 'public') }
  scope :listed, -> { available_accounts.where(visibility: %w(public authenticated password)) }
  scope :published, -> { publicly_accessible }
  scope :featured, -> { publicly_accessible.where('likes_count > 0').order(likes_count: :desc) }

  attr_reader :access_password

  def access_password=(value)
    @access_password = value.presence
    self.access_password_digest = Devise::Encryptor.digest(User, @access_password) if @access_password
  end

  def valid_access_password?(value)
    access_password_digest.present? && value.present? && Devise::Encryptor.compare(User, access_password_digest, value)
  end

  def public_visibility?
    visibility == 'public'
  end

  def authenticated_visibility?
    visibility == 'authenticated'
  end

  def eligible_for_main?
    public_visibility? && !draft?
  end

  def password_visibility?
    visibility == 'password'
  end

  def private_visibility?
    visibility == 'private'
  end

  def access_token
    Rails.application.message_verifier('page_access').generate([id.to_s, updated_at.iso8601(6)], expires_in: 12.hours)
  end

  def valid_access_token?(token)
    page_id, version = Rails.application.message_verifier('page_access').verify(token.to_s)
    page_id == id.to_s && version == updated_at.iso8601(6)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, TypeError
    false
  end

  def liked_by?(account)
    account.present? && page_likes.exists?(account_id: account.id)
  end

  def attached_media
    return MediaAttachment.none if attached_media_ids.empty?

    account.media_attachments.where(id: attached_media_ids)
  end

  def referenced_status_ids
    collect_blocks(content).filter_map { |block| block['note'] if block['type'] == 'note' }.uniq
  end

  def renderable_content
    filter_renderable_blocks(content)
  end

  def renderable_attached_media
    ids = attached_media_ids(renderable_content)
    return MediaAttachment.none if ids.empty?

    account.media_attachments.where(id: ids)
  end

  def self.limit_for(account)
    account.user&.role&.page_limit || DEFAULT_PER_ACCOUNT_LIMIT
  end

  def self.daily_limit_for(account)
    account.user&.role&.daily_page_limit || DEFAULT_DAILY_CREATE_LIMIT
  end

  private

  def synchronize_visibility
    if will_save_change_to_draft? && (!will_save_change_to_visibility? || (new_record? && visibility == 'public'))
      self.visibility = draft? ? 'private' : 'public'
    else
      self.draft = private_visibility?
    end
  end

  def clear_unused_password
    self.access_password_digest = nil unless password_visibility?
  end

  def clear_main_unless_public
    self.is_main = false unless eligible_for_main?
  end

  def validate_access_password
    errors.add(:access_password, :blank) if password_visibility? && access_password_digest.blank?
  end

  def normalize_category
    self.category = category&.strip.presence
  end

  def attached_media_ids(blocks = content)
    collect_blocks(blocks).filter_map { |block| block['fileId'] if block['type'] == 'image' }.uniq
  end

  def collect_blocks(blocks)
    result = []
    pending = Array(blocks).reverse

    until pending.empty?
      block = pending.pop
      next unless block.is_a?(Hash)

      result << block
      pending.concat(block['children'].reverse) if block['children'].is_a?(Array)
    end

    result
  end

  def validate_content
    unless content.is_a?(Array) && content.to_json.bytesize <= MAX_CONTENT_BYTES
      errors.add(:content, :invalid)
      return
    end

    count = 0
    type_counts = Hash.new(0)
    pending = content.reverse.map { |block| [block, 1] }

    until pending.empty?
      block, depth = pending.pop
      count += 1
      type = block['type'] if block.is_a?(Hash)
      type_counts[type] += 1 if type
      type_limit = BLOCK_TYPE_LIMITS[type]

      unless block.is_a?(Hash) && BLOCK_TYPES.include?(type) && count <= MAX_BLOCKS && depth <= MAX_BLOCK_DEPTH && (type_limit.nil? || type_counts[type] <= type_limit) && valid_block_strings?(block)
        errors.add(:content, :invalid)
        return
      end

      children = block['children']
      unless children.nil? || children.is_a?(Array)
        errors.add(:content, :invalid)
        return
      end

      pending.concat(children.reverse.map { |child| [child, depth + 1] }) if children
    end
  end

  def filter_renderable_blocks(blocks, type_counts = Hash.new(0))
    Array(blocks).filter_map do |block|
      next unless block.is_a?(Hash)

      type = block['type']
      type_limit = BLOCK_TYPE_LIMITS[type]
      next if type_limit && type_counts[type] >= type_limit

      type_counts[type] += 1 if type_limit
      result = block.deep_dup
      result['children'] = filter_renderable_blocks(result['children'], type_counts) if result['children'].is_a?(Array)
      result
    end
  end

  def valid_block_strings?(block)
    (!block.key?('text') || (block['text'].is_a?(String) && block['text'].length <= MAX_TEXT_LENGTH)) &&
      (!block.key?('title') || (block['title'].is_a?(String) && block['title'].length <= MAX_SECTION_TITLE_LENGTH)) &&
      (block['type'] != 'youtube' || (valid_youtube_url?(block['url']) && valid_youtube_size?(block['size'])))
  end

  def valid_youtube_url?(url)
    youtube_video_id(url).present?
  end

  def valid_youtube_size?(size)
    size.nil? || YOUTUBE_SIZES.include?(size)
  end

  def youtube_video_id(url)
    return unless url.is_a?(String) && url.length <= MAX_YOUTUBE_URL_LENGTH

    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTPS)

    host = uri.host&.downcase
    video_id = case host
               when 'youtu.be'
                 uri.path.delete_prefix('/').split('/').first
               when 'youtube.com', 'www.youtube.com', 'm.youtube.com'
                 if uri.path == '/watch'
                   URI.decode_www_form(uri.query.to_s).assoc('v')&.last
                 elsif uri.path.match?(%r{\A/(?:embed|shorts)/})
                   uri.path.split('/')[2]
                 end
               end

    video_id if video_id&.match?(YOUTUBE_VIDEO_ID_RE)
  rescue URI::InvalidURIError
    nil
  end

  def validate_attached_media
    ids = attached_media_ids
    return if ids.empty? || account_id.blank?

    valid_ids = ids.all? { |id| id.to_s.match?(/\A\d+\z/) } && account.media_attachments.where(id: ids).count == ids.size
    errors.add(:content, :invalid) unless valid_ids
  end

  def validate_account_pages_limit
    return if account.nil?

    limit = self.class.limit_for(account)
    errors.add(:base, I18n.t('pages.errors.limit', limit: limit)) if account.pages.count >= limit
  end

  def validate_daily_create_limit
    return if account.nil?

    limit = self.class.daily_limit_for(account)
    errors.add(:base, I18n.t('pages.errors.daily_limit', limit: limit)) if account.pages.where(created_at: Time.current.all_day).count >= limit
  end

  def validate_eye_catching_media_attachment
    return if eye_catching_media_attachment.nil? || eye_catching_media_attachment.account_id == account_id

    errors.add(:eye_catching_media_attachment, :invalid)
  end
end
