# frozen_string_literal: true

# == Schema Information
#
# Table name: antenna_tags
#
#  id         :bigint(8)        not null, primary key
#  exclude    :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  antenna_id :bigint(8)        not null
#  tag_id     :bigint(8)        not null
#
class AntennaTag < ApplicationRecord
  belongs_to :antenna
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :antenna_id }

  scope :includes_only, -> { where(exclude: false) }
  scope :excludes_only, -> { where(exclude: true) }
end
