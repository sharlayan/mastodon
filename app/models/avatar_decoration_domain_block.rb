# frozen_string_literal: true

# == Schema Information
#
# Table name: avatar_decoration_domain_blocks
#
#  id         :bigint(8)        not null, primary key
#  domain     :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class AvatarDecorationDomainBlock < ApplicationRecord
  include DomainNormalizable

  validates :domain, presence: true, uniqueness: true, domain: true

  scope :by_domain, ->(domain) { where(domain: domain) }

  def to_log_human_identifier
    domain
  end

  def self.blocked?(domain)
    return false if domain.blank?

    exists?(domain: domain_and_parents(domain))
  end

  def self.blocked_domains_cached
    RequestStore.store[:avatar_decoration_blocked_domains] ||= pluck(:domain).to_set
  end

  def self.blocked_in?(blocked_domains, domain)
    return false if domain.blank?

    domain_and_parents(domain).any? { |candidate| blocked_domains.include?(candidate) }
  end

  def self.domain_and_parents(domain)
    segments = domain.to_s.downcase.split('.')
    Array.new(segments.size) { |index| segments[index..].join('.') }
  end
end
