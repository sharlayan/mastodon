# frozen_string_literal: true

namespace :roleplay do
  desc 'Set every local user\'s notification filters to "accept" (roleplay mode default)'
  # DESTRUCTIVE: overwrites the notification policy of every local account.
  # 파괴적: 모든 로컬 계정의 알림 정책을 덮어씁니다.
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
end
