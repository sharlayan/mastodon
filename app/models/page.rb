# frozen_string_literal: true

# == Schema Information
#
# Table name: pages
#
#  id                               :bigint(8)        not null, primary key
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
  BLOCK_TYPES = %w(text section image note).freeze

  belongs_to :account
  belongs_to :eye_catching_media_attachment, class_name: 'MediaAttachment', optional: true

  has_many :page_likes, inverse_of: :page, dependent: :destroy

  before_validation :normalize_category

  validates :title, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :name, presence: true, length: { maximum: NAME_LENGTH_LIMIT }, format: { with: NAME_RE }, uniqueness: { scope: :account_id }
  validates :summary, length: { maximum: SUMMARY_LENGTH_LIMIT }
  validates :category, length: { maximum: CATEGORY_LENGTH_LIMIT }
  validates :font, inclusion: { in: FONTS }
  validate :validate_content
  validate :validate_eye_catching_media_attachment
  validate :validate_account_pages_limit, on: :create

  scope :published, -> { where(draft: false) }
  scope :featured, -> { published.where('likes_count > 0').order(likes_count: :desc) }

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
