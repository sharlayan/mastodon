# frozen_string_literal: true

class MisskeyCompat::AdminRoleSerializer
  FLAG_POLICIES = { canInvite: :invite_users, canManageCustomEmojis: :manage_custom_emojis }.freeze

  def self.base_policies(compat_policies)
    compat_policies.merge(canInvite: UserRole.everyone.can?(:invite_users), driveCapacityMb: Setting.drive_quota.to_i)
  end

  def self.serialize(role, base_policies:, users_count: nil)
    {
      id: MisskeyCompat::MiId.encode(role.id),
      createdAt: role.created_at&.iso8601,
      updatedAt: role.updated_at&.iso8601,
      name: role.name,
      description: '',
      color: role.color.presence,
      iconUrl: nil,
      target: 'manual',
      condFormula: {},
      isPublic: role.highlighted?,
      isAdministrator: role.administrator?,
      isModerator: role.can?(*UserRole::Flags::CATEGORIES[:moderation]),
      isExplorable: role.highlighted?,
      asBadge: role.highlighted?,
      preserveAssignmentOnMoveAccount: false,
      canEditMembersByModerator: false,
      displayOrder: role.position,
      policies: policies_for(role, base_policies),
      usersCount: users_count || role.users.count,
    }
  end

  def self.policies_for(role, base_policies)
    policies = base_policies.transform_values { |value| { useDefault: true, priority: 0, value: value } }

    FLAG_POLICIES.each do |key, flag|
      policies[key] = { useDefault: false, priority: 0, value: true } if role.permissions.anybits?(UserRole::FLAGS[flag])
    end
    policies[:driveCapacityMb] = { useDefault: false, priority: 0, value: role.drive_quota } unless role.drive_quota.nil?
    policies
  end
end
