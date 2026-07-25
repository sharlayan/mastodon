# frozen_string_literal: true

class RoleplayResetService < BaseService
  RESET_SETTING_KEYS = (
    Sharlayan::RoleplayForcedSettings::SETTINGS.keys +
    %i(force_mfm_enabled force_avatar_decorations force_round_avatar soft_hide_deletion)
  ).freeze

  def call(apply: false)
    raise Mastodon::NotPermittedError if RoleplayModeHelper.roleplay_mode?

    admin_timeline_flag = UserRole::EXTRA_FLAGS.fetch(:view_admin_timeline)
    summary = {
      settings: Setting.where(var: RESET_SETTING_KEYS.map(&:to_s)).count,
      roles: UserRole.where('extra_permissions & ? != 0', admin_timeline_flag).count,
      everyone_role: UserRole.exists?(id: UserRole::EVERYONE_ROLE_ID) ? 1 : 0,
      notification_policies: NotificationPolicy.count,
    }

    reset! if apply
    summary
  end

  private

  def reset!
    ApplicationRecord.transaction do
      Setting.where(var: RESET_SETTING_KEYS.map(&:to_s)).find_each(&:destroy!)
      reset_roles!
      reset_notification_policies!
    end
  end

  def reset_roles!
    admin_timeline_flag = UserRole::EXTRA_FLAGS.fetch(:view_admin_timeline)

    UserRole.find_each do |role|
      attributes = {}
      attributes[:permissions] = UserRole::Flags::DEFAULT if role.id == UserRole::EVERYONE_ROLE_ID
      attributes[:extra_permissions] = role.extra_permissions & ~admin_timeline_flag if role.extra_permissions & admin_timeline_flag != 0
      role.update!(attributes) if attributes.any?
    end
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
