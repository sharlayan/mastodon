# frozen_string_literal: true

class AvatarDecorationDomainBlock < ApplicationRecord
  include DomainNormalizable

  validates :domain, presence: true, uniqueness: true, domain: true

  scope :by_domain, ->(domain) { where(domain: domain) }

  def self.blocked?(domain)
    exists?(domain: domain)
  end

  def self.blocked_domains_cached
    RequestStore.store[:avatar_decoration_blocked_domains] ||= pluck(:domain).to_set
  end
end
