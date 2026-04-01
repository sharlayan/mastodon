# frozen_string_literal: true

class FavoriteEmoji < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :emoji_type, inclusion: { in: %w(custom unicode) }

  scope :ordered, -> { order(:position) }
end
