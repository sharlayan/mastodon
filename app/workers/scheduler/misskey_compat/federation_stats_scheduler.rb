# frozen_string_literal: true

class Scheduler::MisskeyCompat::FederationStatsScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform
    return unless Setting.misskey_compat_enabled

    Sharlayan::FederationAggregationRunner.call { aggregate }
  end

  private

  def aggregate
    now = Time.now.utc

    users = Account.remote.reorder(nil).group(:domain).count
    notes = Status.unscoped.joins(:account).where.not(accounts: { domain: nil }).group('accounts.domain').count
    followers = local_follows_remote_by_domain
    following = remote_follows_local_by_domain
    first_seen = Account.remote.reorder(nil).group(:domain).minimum(:created_at)

    rows = build_rows(domains(users, notes, followers, following), now, users, notes, followers, following, first_seen)
    return if rows.empty?

    MisskeyFederationInstanceStat.upsert_all(rows, unique_by: :domain)
  end

  def local_follows_remote_by_domain
    Follow.unscoped.joins(:account, :target_account)
      .where(accounts: { domain: nil })
      .where.not(target_accounts_follows: { domain: nil })
      .group('target_accounts_follows.domain')
      .count
  end

  def remote_follows_local_by_domain
    Follow.unscoped.joins(:account, :target_account)
      .where.not(accounts: { domain: nil })
      .where(target_accounts_follows: { domain: nil })
      .group('accounts.domain')
      .count
  end

  def domains(*count_maps)
    (count_maps.flat_map(&:keys) + InstanceMetadata.pluck(:domain)).compact.uniq
  end

  def build_rows(domains, now, users, notes, followers, following, first_seen)
    domains.map do |domain|
      {
        domain: domain,
        first_retrieved_at: first_seen[domain],
        users_count: users[domain].to_i,
        notes_count: notes[domain].to_i,
        followers_count: followers[domain].to_i,
        following_count: following[domain].to_i,
        created_at: now,
        updated_at: now,
      }
    end
  end
end
