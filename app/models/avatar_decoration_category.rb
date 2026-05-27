# frozen_string_literal: true

# == Schema Information
#
# Table name: avatar_decoration_categories
#
#  id         :bigint(8)        not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class AvatarDecorationCategory < ApplicationRecord
  has_many :decorations, class_name: 'AvatarDecoration', foreign_key: 'category_id', inverse_of: :category, dependent: nil

  validates :name, presence: true, uniqueness: true

  scope :alphabetic, -> { order(name: :asc) }
end
