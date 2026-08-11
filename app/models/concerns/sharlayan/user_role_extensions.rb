# frozen_string_literal: true

module Sharlayan::UserRoleExtensions
  extend ActiveSupport::Concern

  EXTRA_FLAGS = {
    bypass_rate_limit: (1 << 0),
    view_admin_timeline: (1 << 1),
  }.freeze

  GATED_EXTRA_FLAGS = {
    view_admin_timeline: -> { Sharlayan::AdminTimeline.enabled? },
  }.freeze

  module ExtraFlags
    NONE = 0
    ALL  = EXTRA_FLAGS.values.reduce(0, &:|)
    GATED = EXTRA_FLAGS.values_at(*GATED_EXTRA_FLAGS.keys).reduce(0, &:|)

    CATEGORIES = {
      api: %i(
        bypass_rate_limit
      ).freeze,

      moderation: %i(
        view_admin_timeline
      ).freeze,
    }.freeze
  end

  included do
    validates :drive_quota, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

    validate :validate_extra_permissions_elevation
    validate :validate_sharlayan_own_role_edition
  end

  class_methods do
    def extra_flag_available?(privilege)
      gate = GATED_EXTRA_FLAGS[privilege.to_sym]
      gate.nil? || gate.call
    end

    def unavailable_extra_flags_mask
      GATED_EXTRA_FLAGS.keys.reject { |privilege| extra_flag_available?(privilege) }.sum { |privilege| EXTRA_FLAGS[privilege] }
    end
  end

  def extra_permissions_as_keys
    EXTRA_FLAGS.keys.select { |privilege| extra_permissions & EXTRA_FLAGS[privilege] == EXTRA_FLAGS[privilege] }.map(&:to_s)
  end

  def extra_permissions_as_keys=(value)
    privileges = value.filter_map(&:presence).select { |privilege| self.class.extra_flag_available?(privilege) }

    self.extra_permissions = privileges.reduce(ExtraFlags::NONE) { |bitmask, privilege| EXTRA_FLAGS.key?(privilege.to_sym) ? (bitmask | EXTRA_FLAGS[privilege.to_sym]) : bitmask }
  end

  def can_extra?(*any_of_privileges)
    any_of_privileges.any? { |privilege| in_extra_permissions?(privilege) }
  end

  def drive_quota_bytes
    quota = drive_quota.nil? ? Setting.drive_quota.to_i : drive_quota
    quota.positive? ? quota.megabytes : 0
  end

  def computed_extra_permissions
    raw_computed_extra_permissions & ~self.class.unavailable_extra_flags_mask
  end

  private

  def raw_computed_extra_permissions
    return extra_permissions if everyone?
    return ExtraFlags::NONE if nobody?

    @raw_computed_extra_permissions ||= begin
      computed = self.class.everyone.extra_permissions | extra_permissions
      administrator? ? ExtraFlags::ALL : computed
    end
  end

  def in_extra_permissions?(privilege)
    raise ArgumentError, "Unknown extra privilege: #{privilege}" unless EXTRA_FLAGS.key?(privilege)

    computed_extra_permissions & EXTRA_FLAGS[privilege] == EXTRA_FLAGS[privilege]
  end

  def validate_sharlayan_own_role_edition
    return unless defined?(@current_account) && @current_account.user_role.id == id

    errors.add(:extra_permissions_as_keys, :own_role) if extra_permissions_changed?
    errors.add(:drive_quota, :own_role) if drive_quota_changed? && !administrator?
  end

  def validate_extra_permissions_elevation
    errors.add(:extra_permissions_as_keys, :elevated) if defined?(@current_account) && @current_account.user_role.computed_extra_permissions & extra_permissions != extra_permissions
  end
end
