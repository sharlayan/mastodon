# frozen_string_literal: true

module Sharlayan::Account::DomainMutes
  def muted_from_timeline_domains
    Rails.cache.fetch("mute_domains_for:#{id}") { domain_mutes.pluck(:domain) }
  end
end
