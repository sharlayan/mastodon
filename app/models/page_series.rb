# frozen_string_literal: true

# == Schema Information
#
# Table name: page_series
#
#  id           :bigint(8)        not null, primary key
#  description  :text
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint(8)        not null
#  main_page_id :bigint(8)
#
class PageSeries < ApplicationRecord
  TITLE_LENGTH_LIMIT = 100
  DESCRIPTION_LENGTH_LIMIT = 500
  PER_ACCOUNT_LIMIT = 500

  belongs_to :account
  belongs_to :main_page, class_name: 'Page', optional: true

  has_many :pages, -> { order(:series_position, :id) }, inverse_of: :page_series, dependent: :nullify

  before_validation :normalize_text

  validates :title, presence: true, length: { maximum: TITLE_LENGTH_LIMIT }, uniqueness: { scope: :account_id }
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validate :validate_main_page
  validate :validate_account_series_limit, on: :create

  private

  def normalize_text
    self.title = title&.strip
    self.description = description&.strip.presence
  end

  def validate_main_page
    return if main_page.nil?

    errors.add(:main_page, :invalid) unless main_page.account_id == account_id && main_page.page_series_id == id && main_page.eligible_for_main?
  end

  def validate_account_series_limit
    errors.add(:base, :limit_reached) if account && account.page_series.count >= PER_ACCOUNT_LIMIT
  end
end
