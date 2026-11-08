# frozen_string_literal: true

class ChatMessageReaction < ApplicationRecord
  CUSTOM_EMOJI_RE = /\A:([a-zA-Z0-9_+-]+):\z/

  belongs_to :chat_message, inverse_of: :reactions
  belongs_to :account

  validates :reaction, presence: true, length: { maximum: 100 }
  validates :reaction, uniqueness: { scope: [:chat_message_id, :account_id] }
  validate :recognized_reaction
  validate :message_reaction_limit, on: :create

  attr_writer :custom_emoji

  def self.shortcode_of(reaction)
    reaction&.match(CUSTOM_EMOJI_RE)&.captures&.first
  end

  def self.preload_custom_emojis(reactions)
    pending = reactions.reject(&:custom_emoji_loaded?)
    return reactions if pending.empty?

    ActiveRecord::Associations::Preloader.new(records: pending, associations: :account).call
    wanted = pending.filter_map { |record| (shortcode = shortcode_of(record.reaction)) && [shortcode, record.account&.domain] }.uniq
    emojis = if wanted.empty?
               {}
             else
               CustomEmoji.where(shortcode: wanted.map(&:first).uniq, domain: wanted.map(&:last).uniq, disabled: false)
                 .index_by { |emoji| [emoji.shortcode, emoji.domain] }
             end
    pending.each { |record| record.custom_emoji = emojis[[shortcode_of(record.reaction), record.account&.domain]] }
    reactions
  end

  def custom_emoji
    return @custom_emoji if custom_emoji_loaded?

    shortcode = self.class.shortcode_of(reaction)
    @custom_emoji = shortcode && CustomEmoji.find_by(shortcode: shortcode, domain: account&.domain, disabled: false)
  end

  def custom_emoji_loaded?
    instance_variable_defined?(:@custom_emoji)
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
