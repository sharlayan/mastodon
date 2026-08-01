# frozen_string_literal: true

# == Schema Information
#
# Table name: antennas
#
#  id               :bigint(8)        not null, primary key
#  any_accounts     :boolean          default(TRUE), not null
#  any_domains      :boolean          default(TRUE), not null
#  any_keywords     :boolean          default(TRUE), not null
#  any_tags         :boolean          default(TRUE), not null
#  available        :boolean          default(TRUE), not null
#  exclude_accounts :jsonb            not null
#  exclude_domains  :jsonb            not null
#  exclude_keywords :jsonb            not null
#  exclude_tags     :jsonb            not null
#  ignore_reblog    :boolean          default(FALSE), not null
#  keywords         :jsonb            not null
#  title            :string           default(""), not null
#  with_media_only  :boolean          default(FALSE), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint(8)        not null
#
class Antenna < ApplicationRecord
  include Paginable
  include Redisable

  ANTENNAS_PER_ACCOUNT_LIMIT = 30
  ACCOUNTS_PER_ANTENNA_LIMIT = 100
  DOMAINS_PER_ANTENNA_LIMIT  = 20
  TAGS_PER_ANTENNA_LIMIT     = 50
  KEYWORDS_PER_ANTENNA_LIMIT = 100
  MIN_KEYWORD_LENGTH         = 2
  MAX_KEYWORD_LENGTH         = 256
  TITLE_LENGTH_LIMIT         = 256

  belongs_to :account

  has_many :antenna_accounts, inverse_of: :antenna, dependent: :destroy
  has_many :antenna_domains, inverse_of: :antenna, dependent: :destroy
  has_many :antenna_tags, inverse_of: :antenna, dependent: :destroy

  has_many :accounts, through: :antenna_accounts
  has_many :tags, through: :antenna_tags

  validates :title, presence: true, length: { maximum: TITLE_LENGTH_LIMIT }
  validate :validate_keyword_length
  validate :validate_account_antennas_limit, on: :create

  before_destroy :clean_feed_manager

  scope :availables, -> { where(available: true) }
  scope :configured, -> { where('NOT (antennas.any_accounts AND antennas.any_domains AND antennas.any_tags AND antennas.any_keywords)') }

  def self.matching(status)
    target = status.reblog? ? status.reblog : status
    return [] if target.nil?

    domain = target.account.domain || Rails.configuration.x.local_domain
    tag_ids = target.tags.map(&:id)
    text    = keyword_searchable_text(target)

    domain_antenna_ids  = AntennaDomain.includes_only.where(name: domain).pluck(:antenna_id)
    account_antenna_ids = AntennaAccount.includes_only.where(account_id: target.account_id).pluck(:antenna_id)
    tag_antenna_ids     = AntennaTag.includes_only.where(tag_id: tag_ids).pluck(:antenna_id)

    availables
      .configured
      .where('antennas.any_domains = TRUE OR antennas.id IN (?)', domain_antenna_ids.presence || [-1])
      .where('antennas.any_accounts = TRUE OR antennas.id IN (?)', account_antenna_ids.presence || [-1])
      .where('antennas.any_tags = TRUE OR antennas.id IN (?)', tag_antenna_ids.presence || [-1])
      .includes(:antenna_accounts, :antenna_domains, :antenna_tags, account: :user)
      .select { |antenna| antenna.matches?(status, domain: domain, tag_ids: tag_ids, text: text) }
  end

  def keywords
    self[:keywords] || []
  end

  def exclude_keywords
    self[:exclude_keywords] || []
  end

  def exclude_accounts
    self[:exclude_accounts] || []
  end

  def exclude_domains
    self[:exclude_domains] || []
  end

  def exclude_tags
    self[:exclude_tags] || []
  end

  def last_status_id
    redis.zrevrange(FeedManager.instance.key(:antenna, id), 0, 0).first
  end

  def configured?
    !(any_accounts? && any_domains? && any_tags? && any_keywords?)
  end

  def matches?(status, domain: nil, tag_ids: nil, text: nil)
    return false if status.nil?
    return false unless configured?

    target  = status.reblog? ? status.reblog : status
    account = target.account
    domain  ||= account.domain || Rails.configuration.x.local_domain
    tag_ids ||= target.tags.map(&:id)
    text    ||= self.class.keyword_searchable_text(target)

    return false unless match_domain?(domain)
    return false unless match_account?(account.id)
    return false unless match_tags?(tag_ids)
    return false unless match_keywords?(text)

    return false if exclude_domains.include?(domain)
    return false if excluded_account_ids.include?(account.id)
    return false if (excluded_tag_ids & tag_ids).any?
    return false if exclude_keywords.any? { |keyword| text.include?(keyword) }

    true
  end

  def self.keyword_searchable_text(status)
    status.searchable_text.to_s.gsub(Account::MENTION_RE) { "@#{Regexp.last_match(1).split('@', 2).first}" }
  end

  private

  def match_domain?(domain)
    return true if any_domains?

    antenna_domains.reject(&:exclude?).any? { |item| item.name == domain }
  end

  def match_account?(account_id)
    return true if any_accounts?

    antenna_accounts.reject(&:exclude?).any? { |item| item.account_id == account_id }
  end

  def match_tags?(tag_ids)
    return true if any_tags?

    antenna_tags.reject(&:exclude?).any? { |item| tag_ids.include?(item.tag_id) }
  end

  def match_keywords?(text)
    return true if any_keywords?

    keywords.any? { |keyword| text.include?(keyword) }
  end

  def excluded_account_ids
    exclude_accounts.map(&:to_i)
  end

  def excluded_tag_ids
    exclude_tags.map(&:to_i)
  end

  def validate_account_antennas_limit
    errors.add(:base, I18n.t('antennas.errors.limit')) if account.antennas.count >= ANTENNAS_PER_ACCOUNT_LIMIT
  end

  def validate_keyword_length
    keyword_lists = [keywords, exclude_keywords]

    errors.add(:keywords, I18n.t('antennas.errors.too_many_keywords', limit: KEYWORDS_PER_ANTENNA_LIMIT)) if keyword_lists.any? { |list| list.size > KEYWORDS_PER_ANTENNA_LIMIT }
    errors.add(:keywords, I18n.t('antennas.errors.too_short_keyword', count: MIN_KEYWORD_LENGTH)) if keyword_lists.flatten.any? { |keyword| keyword.to_s.length < MIN_KEYWORD_LENGTH }
    errors.add(:keywords, I18n.t('antennas.errors.too_long_keyword', count: MAX_KEYWORD_LENGTH)) if keyword_lists.flatten.any? { |keyword| keyword.to_s.length > MAX_KEYWORD_LENGTH }
  end

  def clean_feed_manager
    FeedManager.instance.clean_feeds!(:antenna, [id])
  end
end
