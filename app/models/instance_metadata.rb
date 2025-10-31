# frozen_string_literal: true

# == Schema Information
#
# Table name: instance_metadata
#
#  domain                    :string
#  software                  :string
#  version                   :string
#  instance_name             :string
#  theme_color               :string
#  theme_color_updated_at    :datetime
#  favicon_url               :string
#  metadata_updated_at       :datetime
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

  def self.for_domain(domain)
    find_or_create_by(domain: domain)
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
end
