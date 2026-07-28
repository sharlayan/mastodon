# frozen_string_literal: true

class CustomEmojiMuteMatcher
  Identity = Data.define(:shortcode, :domain)

  def initialize(rules)
    @rules = Array(rules)
  end

  def any?
    @rules.any?
  end

  def muted?(shortcode, domain = nil)
    normalized_shortcode = shortcode.to_s.downcase
    normalized_domain = normalize_domain(domain)
    return false if normalized_shortcode.blank?

    @rules.any? do |rule|
      prefix = (rule['prefix'] || rule[:prefix]).to_s
      rule_domain = normalize_domain(rule['domain'] || rule[:domain])

      prefix.present? &&
        (rule_domain.blank? || rule_domain == normalized_domain) &&
        normalized_shortcode.start_with?(prefix)
    end
  end

  def parse(value, domain = nil)
    token = value.to_s.delete_prefix(':').delete_suffix(':')
    shortcode, separator, embedded_domain = token.partition('@')
    resolved_domain = separator.present? ? embedded_domain : domain
    resolved_domain = nil if resolved_domain == '.'

    Identity.new(shortcode:, domain: resolved_domain.to_s)
  end

  private

  def normalize_domain(domain)
    value = domain.to_s.downcase
    value == '.' ? '' : value
  end
end
