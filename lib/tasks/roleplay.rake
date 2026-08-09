# frozen_string_literal: true

namespace :roleplay do
  desc 'Set every local user notification policy to accept in roleplay mode'
  # DESTRUCTIVE: overwrites the notification policy of every local account.
  # 파괴적: 모든 로컬 계정의 알림 정책을 덮어씁니다.
  task accept_all_notifications: :environment do
    abort 'OC_ROLEPLAY_OPTION=true is required' unless RoleplayModeHelper.roleplay_mode?

    Account.local.joins(:user).find_each do |account|
      NotificationPolicy.find_or_initialize_by(account_id: account.id).update!(
        for_not_following: :accept,
        for_not_followers: :accept,
        for_new_accounts: :accept,
        for_private_mentions: :accept
      )
    end
  end
end
