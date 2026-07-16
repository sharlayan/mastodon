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

  PER_ACCOUNT_LIMIT = 100
  TITLE_LENGTH_LIMIT = 256
  NAME_LENGTH_LIMIT = 256
  SUMMARY_LENGTH_LIMIT = 256
  CATEGORY_LENGTH_LIMIT = 30
  NAME_RE = %r{\A[^\s:/?#\[\]@!$&'()*+,;=\\%\x00-\x20]{1,256}\z}
  FONTS = %w(sans-serif serif).freeze
  VISIBILITIES = %w(public password private).freeze
  BLOCK_TYPES = %w(text section image note).freeze

  belongs_to :account
  belongs_to :eye_catching_media_attachment, class_name: 'MediaAttachment', optional: true

  has_many :page_likes, inverse_of: :page, dependent: :destroy
  has_many :page_reports, dependent: :delete_all

  before_validation :normalize_category
  before_validation :synchronize_visibility
  before_validation :clear_unused_password

  validates :title, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :name, presence: true, length: { maximum: NAME_LENGTH_LIMIT }, format: { with: NAME_RE }, uniqueness: { scope: :account_id }
  validates :summary, length: { maximum: SUMMARY_LENGTH_LIMIT }
  validates :category, length: { maximum: CATEGORY_LENGTH_LIMIT }
  validates :font, inclusion: { in: FONTS }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :access_password, length: { in: Devise.password_length }, allow_nil: true
  validate :validate_content
  validate :validate_access_password
  validate :validate_eye_catching_media_attachment
  validate :validate_account_pages_limit, on: :create

  scope :publicly_accessible, -> { where(visibility: 'public') }
  scope :listed, -> { where(visibility: %w(public password)) }
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

  def validate_access_password
    errors.add(:access_password, :blank) if password_visibility? && access_password_digest.blank?
  end

  def normalize_category
    self.category = category&.strip.presence
  end

  def attached_media_ids
    @attached_media_ids ||= collect_blocks(content).filter_map { |block| block['fileId'] if block['type'] == 'image' }.uniq
  end

  def collect_blocks(blocks, acc = [])
    Array(blocks).each do |block|
      next unless block.is_a?(Hash)

      acc << block
      collect_blocks(block['children'], acc) if block['children'].is_a?(Array)
    end
    acc
  end

  def validate_content
    return if content.is_a?(Array) && collect_blocks(content).all? { |block| BLOCK_TYPES.include?(block['type']) }

    errors.add(:content, :invalid)
  end

  def validate_account_pages_limit
    errors.add(:base, I18n.t('pages.errors.limit')) if account.pages.count >= PER_ACCOUNT_LIMIT
  end

  def validate_eye_catching_media_attachment
    return if eye_catching_media_attachment.nil? || eye_catching_media_attachment.account_id == account_id

    errors.add(:eye_catching_media_attachment, :invalid)
  end
end
