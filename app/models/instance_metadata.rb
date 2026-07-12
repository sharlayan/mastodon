# frozen_string_literal: true

# == Schema Information
#
# Table name: instance_metadata
#
#  id                          :bigint(8)        not null, primary key
#  domain                      :string           not null
#  favicon_url                 :string
#  features                    :jsonb            not null
#  instance_name               :string
#  metadata_updated_at         :datetime
#  software                    :string
#  supports_avatar_decorations :boolean          default(FALSE), not null
#  theme_color                 :string
#  theme_color_updated_at      :datetime
#  version                     :string
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#

class InstanceMetadata < ApplicationRecord
  validates :domain, presence: true, uniqueness: true

  DEFAULT_THEME_COLORS = {
    'mastodon' => '#6364FF',
    'misskey' => '#86B300',
    'pleroma' => '#FBA457',
    'akkoma' => '#593196',
    'calckey' => '#31748F',
    'firefish' => '#F07178',
    'sharkey' => '#E85D75',
    'lemmy' => '#00BC8C',
    'kbin' => '#000000',
    'peertube' => '#F1680D',
    'pixelfed' => '#6366F1',
    'gotosocial' => '#DF8958',
    'friendica' => '#3478C8',
    'hubzilla' => '#43488A',
  }.freeze

  REACTION_SOFTWARE = %w(misskey sharkey firefish calckey foundkey magnetar iceshrimp catodon cherrypick akkoma pleroma kmyblue).freeze
  QUOTE_SOFTWARE = %w(misskey sharkey firefish calckey foundkey magnetar iceshrimp catodon cherrypick kmyblue).freeze

  def self.for_domain(domain)
    find_or_create_by(domain: domain)
  end

  def self.cached_by_domain(domain)
    return nil if domain.blank?

    cache = RequestStore.store[:instance_metadata_by_domain] ||= {}
    return cache[domain] if cache.key?(domain)

    cache[domain] = find_by(domain: domain)
  end

  def self.preload_domains(domains)
    cache = RequestStore.store[:instance_metadata_by_domain] ||= {}
    missing = domains.compact.uniq.reject { |domain| domain.blank? || cache.key?(domain) }
    return if missing.empty?

    where(domain: missing).find_each { |metadata| cache[metadata.domain] = metadata }
    missing.each { |domain| cache[domain] ||= nil }
  end

  def default_theme_color
    software_normalized = software&.downcase || 'mastodon'
    DEFAULT_THEME_COLORS[software_normalized] || DEFAULT_THEME_COLORS['mastodon']
  end

  def theme_color_with_fallback
    theme_color.presence || default_theme_color
  end

  def theme_color_needs_update?
    theme_color_updated_at.nil? || theme_color_updated_at < 7.days.ago
  end

  def favicon_url_with_fallback
    favicon_url.presence || "https://#{domain}/favicon.ico"
  end

  def instance_name_with_fallback
    instance_name.presence || domain
  end

  def metadata_needs_update?
    metadata_updated_at.nil? || metadata_updated_at < 1.day.ago
  end

  def software_info_missing?
    software.blank?
  end

  def needs_software_update?
    software_info_missing? && metadata_needs_update?
  end

  def misskey_based?
    return false if software.blank?

    misskey_variants = %w(misskey sharkey firefish calckey foundkey magnetar iceshrimp catodon cherrypick)
    misskey_variants.include?(software.downcase)
  end

  def avatar_decorations_compatible?
    misskey_based? || supports_avatar_decorations?
  end

  def supports_feature?(name)
    return false if features.blank?

    features.include?(name.to_s)
  end

  def software_in?(list)
    return false if software.blank?

    list.include?(software.downcase)
  end

  def server_features
    {
      emoji_reaction: supports_feature?('emoji_reaction') || misskey_based? || software_in?(REACTION_SOFTWARE),
      quote: supports_feature?('quote') || software_in?(QUOTE_SOFTWARE),
      status_reference: supports_feature?('status_reference'),
      circle: supports_feature?('circle'),
      avatar_decorations: avatar_decorations_compatible?,
    }
  end
end
