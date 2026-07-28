# frozen_string_literal: true

# == Schema Information
#
# Table name: clips
#
#  id          :bigint(8)        not null, primary key
#  description :text
#  public      :boolean          default(FALSE), not null
#  title       :string           default(""), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint(8)        not null
#

class Clip < ApplicationRecord
  include Paginable

  PER_ACCOUNT_LIMIT = 100
  STATUSES_LIMIT = 200
  TITLE_LENGTH_LIMIT = 128
  DESCRIPTION_LENGTH_LIMIT = 2048

  belongs_to :account

  has_many :clip_statuses, inverse_of: :clip, dependent: :destroy
  has_many :statuses, through: :clip_statuses
  has_many :clip_favourites, inverse_of: :clip, dependent: :destroy
  has_many :favouriting_accounts, through: :clip_favourites, source: :account

  validates :title, presence: true, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }

  validate :validate_account_clips_limit, on: :create

  scope :public_clips, -> { where(public: true) }

  def visible_to?(account)
    public? || account&.id == account_id
  end

  def favourited_by?(account)
    return false if account.nil?

    clip_favourites.exists?(account_id: account.id)
  end

  private

  def validate_account_clips_limit
    errors.add(:base, I18n.t('clips.errors.limit')) if account.clips.count >= PER_ACCOUNT_LIMIT
  end
end
