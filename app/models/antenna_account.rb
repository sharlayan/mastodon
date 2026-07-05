# frozen_string_literal: true

# == Schema Information
#
# Table name: antenna_accounts
#
#  id         :bigint(8)        not null, primary key
#  exclude    :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  antenna_id :bigint(8)        not null
#
class AntennaAccount < ApplicationRecord
  belongs_to :antenna
  belongs_to :account

  validates :account_id, uniqueness: { scope: :antenna_id }

  scope :includes_only, -> { where(exclude: false) }
  scope :excludes_only, -> { where(exclude: true) }
end
