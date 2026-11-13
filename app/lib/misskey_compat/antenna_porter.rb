# frozen_string_literal: true

class MisskeyCompat::AntennaPorter
  SOURCES = %w(home all users list users_blacklist).freeze
  BOOLEAN_KEYS = %w(caseSensitive localOnly excludeBots withReplies withFile excludeNotesInSensitiveChannel).freeze
  REQUIRED_KEYS = %w(name src keywords excludeKeywords users caseSensitive withReplies withFile).freeze
  BOOLEAN_VALUES = [true, false].freeze
  UNSUPPORTED_FLAGS = %w(caseSensitive localOnly excludeBots excludeNotesInSensitiveChannel).freeze

  def initialize(account)
    @account = account
  end

  def export_json
    antennas = @account.antennas.includes(:antenna_accounts, :antenna_domains, :antenna_tags).order(:id).to_a.select { |antenna| representable?(antenna) }
    accounts = Account.where(id: antennas.flat_map { |antenna| account_ids_for(antenna) }.uniq).index_by(&:id)
    JSON.generate(antennas.map { |antenna| export_entry(antenna, accounts) })
  end

  def import!(entries)
    entries.count { |entry| import_entry(entry) }
  end

  private

  def representable?(antenna)
    antenna.any_domains? && antenna.any_tags? && antenna.exclude_domains.empty? && antenna.exclude_tags.empty?
  end

  def account_ids_for(antenna)
    antenna.antenna_accounts.reject(&:exclude).map(&:account_id) + antenna.exclude_accounts.map(&:to_i)
  end

  def export_entry(antenna, accounts)
    include_ids = antenna.antenna_accounts.reject(&:exclude).map(&:account_id)
    src, user_ids = if !antenna.any_accounts? && include_ids.any?
                      ['users', include_ids]
                    elsif antenna.exclude_accounts.any?
                      ['users_blacklist', antenna.exclude_accounts.map(&:to_i)]
                    else
                      ['all', []]
                    end

    {
      name: antenna.title,
      src: src,
      keywords: nest(antenna.keywords),
      excludeKeywords: nest(antenna.exclude_keywords),
      users: user_ids.filter_map { |id| accounts[id]&.acct },
      userListAccts: nil,
      caseSensitive: false,
      localOnly: false,
      excludeBots: false,
      withReplies: antenna.with_replies,
      withFile: antenna.with_media_only,
      excludeNotesInSensitiveChannel: false,
    }
  end

  def nest(keywords)
    Array(keywords).compact_blank.zip
  end

  def import_entry(entry)
    return false unless importable?(entry)

    src = entry['src'] == 'list' ? 'users' : entry['src']
    users = entry['src'] == 'list' ? entry['userListAccts'] : entry['users']
    account_ids = users.filter_map { |acct| resolve_account(acct)&.id }.uniq

    Antenna.transaction do
      antenna = @account.antennas.new(
        title: entry['name'],
        keywords: flatten(entry['keywords']),
        exclude_keywords: flatten(entry['excludeKeywords']),
        with_replies: entry['withReplies'],
        with_media_only: entry['withFile'],
        any_accounts: src != 'users',
        exclude_accounts: src == 'users_blacklist' ? account_ids.map(&:to_s) : []
      )
      antenna.any_keywords = antenna.keywords.empty?
      @account.with_lock { antenna.save! }
      account_ids.each { |id| antenna.antenna_accounts.create!(account_id: id, exclude: false) } if src == 'users'
    end
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    false
  end

  def importable?(entry)
    return false unless entry.is_a?(Hash) && REQUIRED_KEYS.all? { |key| entry.key?(key) }
    return false unless entry['name'].is_a?(String) && entry['name'].length.between?(1, 100) && SOURCES.include?(entry['src'])
    return false unless keyword_groups?(entry['keywords']) && keyword_groups?(entry['excludeKeywords']) && string_array?(entry['users'])
    return false unless BOOLEAN_KEYS.all? { |key| !entry.key?(key) || BOOLEAN_VALUES.include?(entry[key]) }
    return false unless entry['userListAccts'].nil? || string_array?(entry['userListAccts'])
    return false if entry['keywords'].empty? || entry['keywords'].first.all?('')

    supported?(entry)
  end

  def supported?(entry)
    return false if entry['src'] == 'home' || (entry['src'] == 'list' && entry['userListAccts'].nil?)
    return false if UNSUPPORTED_FLAGS.any? { |key| entry[key] == true }

    (entry['keywords'] + entry['excludeKeywords']).none? { |group| group.compact_blank.size > 1 }
  end

  def keyword_groups?(value)
    value.is_a?(Array) && value.all? { |group| string_array?(group) }
  end

  def string_array?(value)
    value.is_a?(Array) && value.all?(String)
  end

  def flatten(groups)
    groups.flatten.map(&:strip).compact_blank.uniq
  end

  def resolve_account(acct)
    username, domain = acct.delete_prefix('@').split('@', 2)
    return if username.blank?

    domain = nil if domain.present? && domain.casecmp?(Rails.configuration.x.local_domain)
    Account.find_remote(username, domain)
  end
end
