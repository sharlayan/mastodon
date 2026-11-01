# frozen_string_literal: true

class ChatMessageReaction < ApplicationRecord
  belongs_to :chat_message, inverse_of: :reactions
  belongs_to :account

  validates :reaction, presence: true, length: { maximum: 100 }
  validates :reaction, uniqueness: { scope: [:chat_message_id, :account_id] }
  validate :recognized_reaction
  validate :message_reaction_limit, on: :create

  private

  def recognized_reaction
    return if StatusReactionValidator::SUPPORTED_EMOJIS.include?(reaction)

    shortcode = reaction&.match(/\A:([a-zA-Z0-9_+-]+):\z/)&.captures&.first
    return if shortcode && CustomEmoji.exists?(shortcode: shortcode, domain: nil, disabled: false)

    errors.add(:reaction, :invalid)
  end

  def message_reaction_limit
    errors.add(:chat_message, :invalid) if chat_message&.reactions&.count.to_i >= 100
  end
end
