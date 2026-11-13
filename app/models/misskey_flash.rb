# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_flashes
#
#  id          :bigint(8)        not null, primary key
#  likes_count :integer          default(0), not null
#  permissions :string           default([]), not null, is an Array
#  script      :text             default(""), not null
#  summary     :text             default(""), not null
#  title       :string           default(""), not null
#  visibility  :string           default("public"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint(8)        not null
#
class MisskeyFlash < ApplicationRecord
  VISIBILITIES = %w(public private).freeze
  TITLE_LENGTH_LIMIT = 256
  SUMMARY_LENGTH_LIMIT = 1024
  SCRIPT_LENGTH_LIMIT = 65_536
  PERMISSION_LENGTH_LIMIT = 256

  belongs_to :account

  has_many :likes, class_name: 'MisskeyFlashLike', inverse_of: :misskey_flash, dependent: :delete_all

  validates :title, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :summary, length: { maximum: SUMMARY_LENGTH_LIMIT }
  validates :script, length: { maximum: SCRIPT_LENGTH_LIMIT }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validate :validate_permissions

  scope :available_accounts, -> { joins(:account).merge(Account.without_suspended) }
  scope :publicly_listed, -> { available_accounts.where(visibility: 'public') }
  scope :featured, -> { publicly_listed.where(likes_count: 1..).order(likes_count: :desc, updated_at: :desc, id: :desc) }

  def self.matching(query)
    query.to_s.split.reduce(all) do |scope, word|
      pattern = "%#{sanitize_sql_like(word)}%"
      scope.where('misskey_flashes.title ILIKE :pattern OR misskey_flashes.summary ILIKE :pattern', pattern: pattern)
    end
  end

  private

  def validate_permissions
    errors.add(:permissions, :invalid) unless permissions.all? { |permission| permission.is_a?(String) && permission.length <= PERMISSION_LENGTH_LIMIT }
  end
end
