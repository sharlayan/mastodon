# frozen_string_literal: true

class MisskeyCompat::MutedEmojiConverter
  SHORTCODE_RE = /\A[a-zA-Z0-9_]+\z/
  HOST_RE = /\A[a-zA-Z0-9.-]+\z/

  def self.to_misskey(account)
    new(account).to_misskey
  end

  def self.apply(account, emojis)
    new(account).apply(emojis)
  end

  def initialize(account)
    @account = account
  end

  def to_misskey
    compatible_scope.map do |mute|
      mute.domain.present? ? "#{mute.prefix}@#{mute.domain}" : mute.prefix
    end
  end

  def apply(emojis)
    desired = Array(emojis).filter_map { |emoji| parse(emoji) }.uniq
    desired_keys = desired.map { |prefix, domain| [prefix.downcase, domain] }

    existing = compatible_scope.index_by { |mute| [mute.prefix.downcase, mute.domain] }

    existing.each do |key, mute|
      mute.destroy! unless desired_keys.include?(key)
    end

    desired.each do |prefix, domain|
      next if existing.key?([prefix.downcase, domain])

      @account.custom_emoji_mutes.find_or_create_by!(prefix: prefix, domain: domain)
    end
  end

  private

  def compatible_scope
    @account.custom_emoji_mutes.where(reject_reactions: false, hide_in_picker: false).order(id: :desc)
  end

  def parse(emoji)
    return nil unless emoji.is_a?(String)

    value = emoji.delete_prefix(':').delete_suffix(':').strip
    return nil if value.blank?

    prefix, _, host = value.partition('@')
    return nil unless prefix.match?(SHORTCODE_RE)
    return nil if host.present? && !host.match?(HOST_RE)

    [prefix, host.presence.to_s]
  end
end
