# frozen_string_literal: true

# == Schema Information
#
# Table name: antenna_domains
#
#  id         :bigint(8)        not null, primary key
#  exclude    :boolean          default(FALSE), not null
#  name       :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  antenna_id :bigint(8)        not null
#
class AntennaDomain < ApplicationRecord
  belongs_to :antenna

  validates :name, presence: true
  validates :name, uniqueness: { scope: :antenna_id }

  scope :includes_only, -> { where(exclude: false) }
  scope :excludes_only, -> { where(exclude: true) }
end
