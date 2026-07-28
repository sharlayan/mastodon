# frozen_string_literal: true

class CustomEmojiResponseFilter
  REPLACEMENT = '⬛'
  TEXT_KEYS = %w(content text cw spoiler_text display_name note title value name).freeze

  def self.filter(payload, rules)
    matcher = CustomEmojiMuteMatcher.new(rules)
    return payload unless matcher.any?

    new(matcher).filter(payload)
  end

  def initialize(matcher)
    @matcher = matcher
  end

  def filter(payload)
    visit(payload)
    payload
  end

  private

  def visit(value, inherited_identities = [])
    case value
    when Array
      value.reject! { |item| muted_reaction_notification?(item) }
      value.each { |item| visit(item, inherited_identities) }
    when Hash
      filter_hash(value, inherited_identities)
    end
  end

  def filter_hash(hash, inherited_identities)
    identities = inherited_identities + filter_emoji_metadata(hash)
    filter_reactions(hash)
    replace_text(hash, identities)
    hash.each_value { |value| visit(value, identities) }
  end

  def filter_emoji_metadata(hash)
    emojis_key = existing_key(hash, 'emojis')
    return [] unless emojis_key

    emojis = hash[emojis_key]

    case emojis
    when Array
      filter_rest_emojis(emojis)
    when Hash
      filter_misskey_emojis(emojis)
    else
      []
    end
  end

  def filter_rest_emojis(emojis)
    removed = []

    emojis.reject! do |emoji|
      next false unless emoji.is_a?(Hash)

      identity = @matcher.parse(fetch(emoji, 'shortcode'), fetch(emoji, 'domain'))
      @matcher.muted?(identity.shortcode, identity.domain).tap do |muted|
        removed << identity if muted
      end
    end

    removed
  end

  def filter_misskey_emojis(emojis)
    removed = []

    emojis.delete_if do |name, _url|
      identity = @matcher.parse(name)
      @matcher.muted?(identity.shortcode, identity.domain).tap do |muted|
        removed << identity if muted
      end
    end

    removed
  end

  def filter_reactions(hash)
    reactions_key = existing_key(hash, 'reactions')
    return unless reactions_key

    reactions = hash[reactions_key]

    if reactions.is_a?(Array)
      reactions.reject! do |reaction|
        reaction.is_a?(Hash) &&
          fetch(reaction, 'url').present? &&
          muted_identity?(fetch(reaction, 'name'), fetch(reaction, 'domain'))
      end
    elsif reactions.is_a?(Hash)
      reactions.delete_if { |name, _count| custom_reaction?(name) && muted_identity?(name) }
      filter_reaction_emoji_map(hash)

      my_reaction_key = existing_key(hash, 'myReaction')
      hash[my_reaction_key] = nil if my_reaction_key && custom_reaction?(hash[my_reaction_key]) && muted_identity?(hash[my_reaction_key])
    end
  end

  def filter_reaction_emoji_map(hash)
    key = existing_key(hash, 'reactionEmojis')
    return unless key && hash[key].is_a?(Hash)

    hash[key].delete_if { |name, _url| muted_identity?(name) }
  end

  def replace_text(hash, identities)
    return if identities.empty?

    TEXT_KEYS.each do |name|
      key = existing_key(hash, name)
      next unless key && hash[key].is_a?(String)

      identities.each do |identity|
        hash[key] = hash[key].gsub(/:#{Regexp.escape(identity.shortcode)}:/i, REPLACEMENT)
      end
    end
  end

  def muted_identity?(name, domain = nil)
    identity = @matcher.parse(name, domain)
    @matcher.muted?(identity.shortcode, identity.domain)
  end

  def muted_reaction_notification?(value)
    return false unless value.is_a?(Hash) && fetch(value, 'type').to_s == 'reaction'

    reaction = fetch(value, 'reaction')
    reaction.is_a?(Hash) &&
      fetch(reaction, 'url').present? &&
      muted_identity?(fetch(reaction, 'name'), fetch(reaction, 'domain'))
  end

  def custom_reaction?(name)
    name.to_s.start_with?(':') && name.to_s.end_with?(':')
  end

  def existing_key(hash, name)
    return name if hash.key?(name)

    symbol = name.to_sym
    symbol if hash.key?(symbol)
  end

  def fetch(hash, name)
    key = existing_key(hash, name)
    hash[key] if key
  end
end
