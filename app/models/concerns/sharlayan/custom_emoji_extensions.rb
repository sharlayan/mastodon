# frozen_string_literal: true

module Sharlayan::CustomEmojiExtensions
  extend ActiveSupport::Concern

  LOCAL_LIMIT = (ENV['MAX_EMOJI_SIZE'] || 20.megabytes).to_i
  LIMIT       = [LOCAL_LIMIT, (ENV['MAX_REMOTE_EMOJI_SIZE'] || 20.megabytes).to_i].max

  SHORTCODE_RE_FRAGMENT = '[a-zA-Z0-9_]{1,}'

  SCAN_RE = /(?<=[^a-zA-Z0-9_]|\n|^)
    :(#{SHORTCODE_RE_FRAGMENT}):
    (?=[^a-zA-Z0-9_]|$)/x
  SHORTCODE_ONLY_RE = /\A#{SHORTCODE_RE_FRAGMENT}\z/

  IMAGE_MIME_TYPES = %w(image/png image/gif image/webp image/jpeg).freeze

  ALIASES_MAX_COUNT  = 20
  ALIAS_MAX_LENGTH   = 100
  LICENSE_MAX_LENGTH = 500

  included do
    attr_accessor :aliases_raw

    validates :license, length: { maximum: LICENSE_MAX_LENGTH }, allow_blank: true
    validate :validate_aliases_count_and_length
  end

  class_methods do
    def search(shortcode)
      pattern = "%#{sanitize_sql_like(shortcode)}%"
      where(arel_table[:shortcode].matches(pattern))
        .or(where('EXISTS (SELECT 1 FROM unnest(custom_emojis.aliases) AS alias WHERE alias ILIKE :pattern)', pattern: pattern))
    end
  end

  private

  def validate_aliases_count_and_length
    return if aliases.blank?

    errors.add(:aliases, :too_many, max: ALIASES_MAX_COUNT) if aliases.size > ALIASES_MAX_COUNT

    aliases.each do |alias_name|
      if alias_name.length > ALIAS_MAX_LENGTH
        errors.add(:aliases, :too_long, max: ALIAS_MAX_LENGTH)
        break
      end
    end
  end
end
