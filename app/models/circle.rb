# frozen_string_literal: true

# == Schema Information
#
# Table name: circles
#
#  id         :bigint(8)        not null, primary key
#  title      :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#

class Circle < ApplicationRecord
  include Paginable

  PER_ACCOUNT_LIMIT = 100
  ACCOUNTS_PER_CIRCLE_LIMIT = 100
  ACCOUNTS_PER_REQUEST_LIMIT = 100

  belongs_to :account

  has_many :circle_accounts, inverse_of: :circle, dependent: :destroy
  has_many :accounts, through: :circle_accounts
  has_many :circle_statuses, inverse_of: :circle, dependent: :destroy
  has_many :statuses, through: :circle_statuses

  validates :title, presence: true

  validate :validate_account_circles_limit, on: :create

  private

  def validate_account_circles_limit
    errors.add(:base, I18n.t('circles.errors.limit')) if account.circles.count >= PER_ACCOUNT_LIMIT
  end
end
