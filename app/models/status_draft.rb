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
  MAX_DATA_BYTES = 64.kilobytes
  MAX_ACCOUNT_DATA_BYTES = 2.megabytes
  LIST_LIMIT = 20

  belongs_to :account, inverse_of: :status_drafts
  has_many :media_attachments, -> { order(:id) }, inverse_of: :status_draft, dependent: :nullify

  validates :data, presence: true
  validate :validate_data_size
  validate :validate_account_storage
  validate :validate_account_limit, on: :create

  scope :within_data_limit, -> { where('octet_length(status_drafts.data::text) <= ?', MAX_DATA_BYTES) }

  def data_bytes
    JSON.generate(data).bytesize
  rescue JSON::GeneratorError, TypeError
    MAX_DATA_BYTES + 1
  end

  private

  def validate_data_size
    errors.add(:data, I18n.t('status_drafts.data_too_large', limit: MAX_DATA_BYTES / 1.kilobyte)) if data_bytes > MAX_DATA_BYTES
  end

  def validate_account_storage
    return if account.nil? || data_bytes > MAX_DATA_BYTES

    other_bytes = account.status_drafts.where.not(id: id).sum(Arel.sql('octet_length(status_drafts.data::text)')).to_i
    projected_bytes = other_bytes + data_bytes
    return if projected_bytes <= MAX_ACCOUNT_DATA_BYTES

    stored_bytes = persisted? ? self.class.where(id: id).pick(Arel.sql('octet_length(status_drafts.data::text)')).to_i : 0
    return if projected_bytes < other_bytes + stored_bytes

    errors.add(:base, I18n.t('status_drafts.storage_too_large', limit: MAX_ACCOUNT_DATA_BYTES / 1.megabyte))
  end

  def validate_account_limit
    return if account.nil?

    errors.add(:base, I18n.t('status_drafts.over_limit', limit: LIMIT)) if account.status_drafts.count >= LIMIT
  end
end
