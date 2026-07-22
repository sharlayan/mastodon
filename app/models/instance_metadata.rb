# frozen_string_literal: true

require 'request_store'

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
    # Mastodon family
    # Icon source: https://github.com/mastodon/mastodon/blob/main/app/javascript/images/logo-symbol-icon.svg
    'mastodon' => '#6364FF',
    'kmyblue' => '#6364FF',

    # Misskey family
    # Icon source: https://github.com/misskey-dev/misskey/blob/159b1a44/packages/backend/assets/favicon.png
    'misskey' => '#A1CA03',
    'calckey' => '#31748F',
    'firefish' => '#F07A5B',
    'sharkey' => '#E85D75',
    'foundkey' => '#A1CA03',
    'magnetar' => '#A1CA03',
    'iceshrimp' => '#A1CA03',
    'catodon' => '#A1CA03',
    'cherrypick' => '#A1CA03',

    # Pleroma family
    # Icon source: https://git.pleroma.social/pleroma/pleroma/-/blob/0a076443/priv/static/static/logo.svg
    'pleroma' => '#FBA457',
    'akkoma' => '#593196',

    # Kbin family
    'kbin' => '#000000',
    'mbin' => '#00BC8C',

    # Fedify framework and implementations
    # Icon source: https://github.com/fedify-dev/fedify/blob/c2352c0e/logo.svg
    'fedify' => '#0284C7',
    # Icon source: https://github.com/fedify-dev/hollo/blob/56f37f74/docs/public/favicon.svg
    'hollo' => '#000000',
    # Icon source: https://github.com/hackers-pub/hackerspub/blob/346a7aa4/web/static/favicon.svg
    'hackerspub' => '#000000',

    # Independent software
    'lemmy' => '#00BC8C',
    # Icon source: https://github.com/Chocobozzz/PeerTube/blob/fe0da961/client/src/assets/images/logo.svg
    'peertube' => '#F1680D',
    # Icon source: https://github.com/pixelfed/pixelfed/blob/c8bed78b/public/img/pixelfed-icon-color.svg
    'pixelfed' => '#6366F1',
    'gotosocial' => '#DF8958',
    'friendica' => '#3478C8',
    'hubzilla' => '#43488A',
    'bookwyrm' => '#00D1B2',
    'writefreely' => '#292929',
    'funkwhale' => '#009FE3',
    'owncast' => '#7871FF',
    'mobilizon' => '#FFD599',
  }.freeze

  PINNED_THEME_COLORS = {
    'bsky.brid.gy' => '#1185FE',
  }.freeze

  REACTION_SOFTWARE = %w(kmyblue misskey calckey firefish sharkey foundkey magnetar iceshrimp catodon cherrypick pleroma akkoma hollo hackerspub).freeze
  QUOTE_SOFTWARE = %w(kmyblue misskey calckey firefish sharkey foundkey magnetar iceshrimp catodon cherrypick hollo hackerspub).freeze

  FEATURE_WIRE_MAP = {
    emoji_reaction: 'emoji_reaction',
    quote: 'quote',
    circle: 'circle',
    status_reference: 'status_reference',
    mfm: 'mfm',
    avatar_decorations: 'avatarDecorations',
  }.freeze

  WIRE_FEATURE_MAP = FEATURE_WIRE_MAP.to_h { |internal, wire| [wire, internal.to_s] }.freeze

  def self.features_to_wire(internal_features)
    Array(internal_features).filter_map { |feature| FEATURE_WIRE_MAP[feature.to_sym] }
  end

  def self.features_from_wire(wire_features)
    return [] unless wire_features.is_a?(Array)

    wire_features.filter_map { |feature| WIRE_FEATURE_MAP[feature] }.uniq
  end

  def self.advertised_features
    features = []
    features << :emoji_reaction if Setting.reactions_enabled
    features << :quote
    features << :circle if Setting.circles_enabled
    features << :mfm if Setting.mfm_enabled
    features << :avatar_decorations if Setting.avatar_decorations_enabled && Setting.avatar_decorations_federation_enabled
    features
  end

  def self.local_server_features
    {
      emoji_reaction: Setting.reactions_enabled,
      quote: true,
      status_reference: false,
      circle: Setting.circles_enabled,
      avatar_decorations: Setting.avatar_decorations_enabled,
    }
  end

  def self.blank_server_features
    {
      emoji_reaction: false,
      quote: false,
      status_reference: false,
      circle: false,
      avatar_decorations: false,
    }
  end

  def self.for_domain(domain)
    find_or_create_by(domain: domain)
  end

  def self.cached_by_domain(domain)
    return nil if domain.blank?

    cache = RequestStore.store[:instance_metadata_by_domain] ||= {}
    return cache[domain] if cache.key?(domain)

    cache[domain] = find_by(domain: domain)
  end

  def self.cached_find_or_create_by_domain(domain)
    metadata = cached_by_domain(domain)
    return metadata if metadata.present?

    metadata = for_domain(domain)
    RequestStore.store[:instance_metadata_by_domain][domain] = metadata
  end

  def self.preload_domains(domains)
    cache = RequestStore.store[:instance_metadata_by_domain] ||= {}
    missing = domains.compact.uniq.reject { |domain| domain.blank? || cache.key?(domain) }
    return if missing.empty?

    where(domain: missing).find_each { |metadata| cache[metadata.domain] = metadata }
    missing.each { |domain| cache[domain] ||= nil }
  end

  def theme_color
    PINNED_THEME_COLORS[domain] || super
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
