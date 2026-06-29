# frozen_string_literal: true

# == Schema Information
#
# Table name: board_announcement_reactions
#
#  id                    :bigint(8)        not null, primary key
#  name                  :string           default(""), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint(8)        not null
#  board_announcement_id :bigint(8)        not null
#  custom_emoji_id       :bigint(8)
#

class BoardAnnouncementReaction < ApplicationRecord
  before_validation :set_custom_emoji, if: :name?

  belongs_to :account
  belongs_to :board_announcement, inverse_of: :board_announcement_reactions
  belongs_to :custom_emoji, optional: true

  validates :name, presence: true
  validates_with ReactionValidator

  private

  def set_custom_emoji
    self.custom_emoji = CustomEmoji.local.enabled.find_by(shortcode: name)
  end
end
