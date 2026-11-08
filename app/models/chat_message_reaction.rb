# frozen_string_literal: true

class ChatMessageReaction < ApplicationRecord
  CUSTOM_EMOJI_RE = /\A:([a-zA-Z0-9_+-]+):\z/

  belongs_to :chat_message, inverse_of: :reactions
  belongs_to :account

  validates :reaction, presence: true, length: { maximum: 100 }
  validates :reaction, uniqueness: { scope: [:chat_message_id, :account_id] }
  validate :recognized_reaction
  validate :message_reaction_limit, on: :create

  def self.shortcode_of(reaction)
    reaction&.match(CUSTOM_EMOJI_RE)&.captures&.first
  end

  def custom_emoji
    shortcode = self.class.shortcode_of(reaction)
    shortcode && CustomEmoji.find_by(shortcode: shortcode, domain: account&.domain, disabled: false)
  end

  private

  def recognized_reaction
    return if StatusReactionValidator::SUPPORTED_EMOJIS.include?(reaction)

    shortcode = self.class.shortcode_of(reaction)
    return if shortcode && (account&.remote? || CustomEmoji.exists?(shortcode: shortcode, domain: nil, disabled: false))

    errors.add(:reaction, :invalid)
  end

  def message_reaction_limit
    errors.add(:chat_message, :invalid) if chat_message&.reactions&.count.to_i >= 100
  end
end
