# frozen_string_literal: true

module MfmDetector
  MFM_PATTERN = /\$\[(\w+)(?:[.\s])/

  ALLOWED_TAGS = %w(
    tada jelly twitch shake spin jump bounce flip
    x2 x3 x4 scale position
    fg bg border font blur rainbow sparkle rotate
    ruby unixtime
  ).freeze

  def self.contains_mfm?(text)
    extract_tags(text).any?
  end

  def self.extract_tags(text)
    return [] if text.blank?

    text.scan(MFM_PATTERN).flatten.uniq.select { |tag| ALLOWED_TAGS.include?(tag) }
  end
end
