# frozen_string_literal: true

# == Schema Information
#
# Table name: status_drafts
#
#  id         :bigint(8)        not null, primary key
#  data       :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#
class StatusDraft < ApplicationRecord
  include Paginable

  LIMIT = 100

  belongs_to :account, inverse_of: :status_drafts
  has_many :media_attachments, -> { order(:id) }, inverse_of: :status_draft, dependent: :nullify

  validates :data, presence: true
  validate :validate_account_limit, on: :create

  private

  def validate_account_limit
    return if account.nil?

    errors.add(:base, I18n.t('status_drafts.over_limit', limit: LIMIT)) if account.status_drafts.count >= LIMIT
  end
end
