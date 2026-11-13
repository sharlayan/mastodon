# frozen_string_literal: true

module Sharlayan::RegistrationRejectionPatterns
  MAX_LENGTH = 8192
  MAX_PATTERNS = 100
  MATCH_TIMEOUT = 0.02

  module_function

  def entries(value)
    value.to_s.lines.map(&:strip).compact_blank
  end

  def valid?(value)
    return false if value.to_s.length > MAX_LENGTH

    patterns = entries(value)
    patterns.size <= MAX_PATTERNS && patterns.all? { |pattern| compile(pattern) }
  rescue RegexpError, ArgumentError
    false
  end

  def match?(text, value)
    return false if text.blank? || text.length > 320

    entries(value.to_s.first(MAX_LENGTH)).first(MAX_PATTERNS).any? do |pattern|
      matches_pattern?(text, pattern)
    end
  end

  def matches_pattern?(text, pattern)
    compiled = compile(pattern)
    compiled.is_a?(Regexp) ? compiled.match?(text) : text.include?(compiled)
  rescue Regexp::TimeoutError
    true
  rescue RegexpError, ArgumentError
    false
  end

  def compile(pattern)
    return pattern unless pattern.start_with?('?')

    raise RegexpError if pattern.length == 1

    Regexp.new(pattern.delete_prefix('?'), timeout: MATCH_TIMEOUT)
  end
end
