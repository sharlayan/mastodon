# frozen_string_literal: true

namespace :roleplay do
  desc 'Set every local user\'s notification filters to "accept" (roleplay mode default)'
  task accept_all_notifications: :environment do
    abort 'OC_ROLEPLAY_OPTION=true is required' unless RoleplayModeHelper.roleplay_mode?

    updated = 0

    Account.local.joins(:user).find_each do |account|
      policy = NotificationPolicy.find_or_initialize_by(account_id: account.id)

      policy.assign_attributes(
        for_not_following: :accept,
        for_not_followers: :accept,
        for_new_accounts: :accept,
        for_private_mentions: :accept
      )

      next unless policy.new_record? || policy.changed?

      ActiveRecord::Base.logger.silence do
        policy.save!
      end

      updated += 1
    end

    puts "Updated notification policies for #{updated} local account(s)."
  end

  desc 'Hide (owner-only) all local statuses posted up to a cutoff (trial end). Usage: rake roleplay:hide_period BEFORE=2026-07-13 [AFTER=2026-07-01]'
  task hide_period: :environment do
    abort 'OC_ROLEPLAY_OPTION=true is required' unless RoleplayModeHelper.roleplay_mode?
    abort 'soft_hide_deletion must be enabled' unless Setting.soft_hide_deletion

    before = ENV.fetch('BEFORE') { abort 'BEFORE is required (e.g. BEFORE=2026-07-13 or a full timestamp).' }
    after  = ENV.fetch('AFTER', nil)

    max_id = Mastodon::Snowflake.id_at(Time.zone.parse(before), with_random: false)
    min_id = after.present? ? Mastodon::Snowflake.id_at(Time.zone.parse(after), with_random: false) : nil

    scope = Status.with_rp_hidden.local.where(id: ..max_id)
    scope = scope.where(id: min_id..) if min_id

    total  = 0
    hidden = 0

    scope.reorder(id: :desc).find_each do |status|
      total += 1
      next if status.rp_hidden?

      HideStatusService.new.call(status)
      hidden += 1
      puts "  hidden #{hidden}..." if (hidden % 500).zero?
    end

    puts "Scanned #{total} local status(es), newly hidden #{hidden}."
  end
end
