# frozen_string_literal: true

module Sharlayan::SilentInteractionDelivery
  DOMAINS = %w(bird.makeup).freeze
  SOFTWARE = %w(birdsitelive).freeze

  def self.suppressed_for?(account)
    return false if account.nil? || account.local?

    domain = account.domain.to_s.downcase
    return true if DOMAINS.include?(domain)

    InstanceMetadata.cached_by_domain(domain)&.software_in?(SOFTWARE) == true
  end

  def self.quote_policy_ignored_for?(status)
    suppressed_for?(status&.account)
  end

  def self.reply_suppressed_for?(status)
    suppressed_for?(status&.account)
  end
end
