# frozen_string_literal: true

class RoleplayResetService < BaseService
  RESET_SETTING_KEYS = (
    Sharlayan::RoleplayForcedSettings::SETTINGS.keys +
    %i(force_mfm_enabled force_avatar_decorations force_round_avatar)
  ).freeze

  def call(apply: false)
    raise Mastodon::NotPermittedError if RoleplayModeHelper.roleplay_mode?

    summary = {
      settings: Setting.where(var: RESET_SETTING_KEYS.map(&:to_s)).count,
      everyone_role: UserRole.exists?(id: UserRole::EVERYONE_ROLE_ID) ? 1 : 0,
      notification_policies: NotificationPolicy.count,
    }

    reset! if apply
    summary
  end

  private

  # DESTRUCTIVE: deletes the setting rows and rewrites every role and notification policy. Not reversible.
  # 파괴적: 설정 행을 삭제하고 모든 역할과 알림 정책을 덮어씁니다. 되돌릴 수 없습니다.
  def reset!
    ApplicationRecord.transaction do
      Setting.where(var: RESET_SETTING_KEYS.map(&:to_s)).find_each(&:destroy!)
      reset_roles!
      reset_notification_policies!
    end
  end

  def reset_roles!
    everyone = UserRole.find_by(id: UserRole::EVERYONE_ROLE_ID)
    everyone&.update!(permissions: UserRole::Flags::DEFAULT)
  end

  def reset_notification_policies!
    NotificationPolicy.find_each do |policy|
      policy.update!(
        for_not_following: :accept,
        for_not_followers: :accept,
        for_new_accounts: :accept,
        for_private_mentions: :filter
      )
    end
  end
end
