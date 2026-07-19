# frozen_string_literal: true

# == Schema Information
#
# Table name: favorite_emojis
#
#  id         :bigint(8)        not null, primary key
#  emoji_type :string           not null
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#
class FavoriteEmoji < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :emoji_type, inclusion: { in: %w(custom unicode) }

  scope :ordered, -> { order(:position) }
end
