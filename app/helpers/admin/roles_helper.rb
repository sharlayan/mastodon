# frozen_string_literal: true

module Admin
  module RolesHelper
    def privilege_label(privilege)
      safe_join(
        [
          t("admin.roles.privileges.#{privilege}"),
          content_tag(:span, t("admin.roles.privileges.#{privilege}_description"), class: 'hint'),
        ]
      )
    end

    def disable_permissions?(permissions)
      permissions.filter { |privilege| role_flag_value(privilege).zero? }
    end

    def extra_privilege_label(privilege)
      safe_join(
        [
          t("admin.roles.extra_privileges.#{privilege}"),
          content_tag(:span, t("admin.roles.extra_privileges.#{privilege}_description"), class: 'hint'),
        ]
      )
    end

    def disable_extra_permissions?(permissions)
      permissions.filter do |privilege|
        if privilege == :bypass_rate_limit
          !can_manage_rate_limits?
        else
          role_extra_flag_value(privilege).zero?
        end
      end
    end

    def can_manage_rate_limits?
      @can_manage_rate_limits ||= current_user.role.administrator? || (!current_user.role.everyone? && current_user.role.position == UserRole.assignable.maximum(:position))
    end

    private

    def role_flag_value(privilege)
      UserRole::FLAGS[privilege] & current_user.role.computed_permissions
    end

    def role_extra_flag_value(privilege)
      UserRole::EXTRA_FLAGS[privilege] & current_user.role.computed_extra_permissions
    end
  end
end
