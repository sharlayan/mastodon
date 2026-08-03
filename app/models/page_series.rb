# frozen_string_literal: true

# == Schema Information
#
# Table name: page_series
#
#  id                        :bigint(8)        not null, primary key
#  description               :text
#  displayed                 :boolean          default(TRUE), not null
#  title                     :string           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint(8)        not null
#  cover_media_attachment_id :bigint(8)
#  main_page_id              :bigint(8)
#
class PageSeries < ApplicationRecord
  TITLE_LENGTH_LIMIT = 100
  DESCRIPTION_LENGTH_LIMIT = 500
  PER_ACCOUNT_LIMIT = 500

  belongs_to :account
  belongs_to :cover_media_attachment, class_name: 'MediaAttachment', optional: true
  belongs_to :main_page, class_name: 'Page', optional: true

  has_many :pages, -> { order(:series_position, :id) }, inverse_of: :page_series, dependent: :nullify

  before_validation :normalize_text

  validates :title, presence: true, length: { maximum: TITLE_LENGTH_LIMIT }, uniqueness: { scope: :account_id }
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validates :displayed, inclusion: { in: [true, false] }
  validate :validate_main_page
  validate :validate_cover_media_attachment
  validate :validate_account_series_limit, on: :create

  def entry_page(preloaded_pages: nil)
    return main_page if valid_main_page?(main_page)

    return preloaded_pages.select(&:eligible_for_main?).min_by { |page| [page.created_at, page.id] } if preloaded_pages

    pages.where(visibility: 'public', draft: false).reorder(:created_at, :id).first
  end

  private

  def normalize_text
    self.title = title&.strip
    self.description = description&.strip.presence
  end

  def validate_main_page
    return if main_page.nil?

    errors.add(:main_page, :invalid) unless valid_main_page?(main_page)
  end

  def valid_main_page?(page)
    page&.account_id == account_id && page.page_series_id == id && page.eligible_for_main?
  end

  def validate_cover_media_attachment
    return if cover_media_attachment.nil? || cover_media_attachment.account_id == account_id

    errors.add(:cover_media_attachment, :invalid)
  end

  def validate_account_series_limit
    errors.add(:base, :limit_reached) if account && account.page_series.count >= PER_ACCOUNT_LIMIT
  end
end
