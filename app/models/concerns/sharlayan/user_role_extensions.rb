# frozen_string_literal: true

module Sharlayan::UserRoleExtensions
  extend ActiveSupport::Concern
  include Redisable

  EXTRA_FLAGS = {
    bypass_rate_limit: (1 << 0),
    view_admin_timeline: (1 << 1),
    view_followers_admin_timeline: (1 << 2),
  }.freeze

  GATED_EXTRA_FLAGS = {
    view_admin_timeline: -> { Sharlayan::AdminTimeline.enabled? },
    view_followers_admin_timeline: -> { Sharlayan::AdminTimeline.enabled? },
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
        view_followers_admin_timeline
      ).freeze,
    }.freeze
  end

  included do
    validates :drive_quota, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

    validate :validate_extra_permissions_elevation
    validate :validate_sharlayan_own_role_edition

    before_save :capture_admin_timeline_stream_accounts, if: :admin_timeline_authorization_will_change?
    before_destroy :capture_admin_timeline_stream_accounts
    after_commit :reauthorize_admin_timeline_stream_accounts, on: %i(create update destroy)
    after_rollback :clear_admin_timeline_stream_accounts
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
    return implied_extra_permissions(extra_permissions) if everyone?
    return ExtraFlags::NONE if nobody?

    @raw_computed_extra_permissions ||= begin
      computed = self.class.everyone.extra_permissions | extra_permissions
      administrator? ? ExtraFlags::ALL : implied_extra_permissions(computed)
    end
  end

  def implied_extra_permissions(permissions)
    return permissions unless permissions & EXTRA_FLAGS[:view_admin_timeline] == EXTRA_FLAGS[:view_admin_timeline]

    permissions | EXTRA_FLAGS[:view_followers_admin_timeline]
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

  def admin_timeline_authorization_will_change?
    Sharlayan::AdminTimeline.enabled? && (new_record? || will_save_change_to_permissions? || will_save_change_to_extra_permissions? || will_save_change_to_position?)
  end

  def capture_admin_timeline_stream_accounts
    return unless Sharlayan::AdminTimeline.enabled?

    @admin_timeline_stream_account_ids = users.where.not(account_id: nil).pluck(:account_id) | admin_timeline_viewer_account_ids
  end

  def reauthorize_admin_timeline_stream_accounts
    return unless defined?(@admin_timeline_stream_account_ids)

    account_ids = @admin_timeline_stream_account_ids | admin_timeline_viewer_account_ids
    payload = { event: :kill }.to_json
    with_redis { |connection| account_ids.each { |account_id| connection.publish("timeline:system:#{account_id}", payload) } }
  ensure
    clear_admin_timeline_stream_accounts
  end

  def admin_timeline_viewer_account_ids
    viewer_roles = self.class.select { |role| Sharlayan::AdminTimeline.role_can_view?(role) }
    users = User.where.not(account_id: nil)

    viewer_roles.any?(&:everyone?) ? users.pluck(:account_id) : users.where(role_id: viewer_roles.map(&:id)).pluck(:account_id)
  end

  def clear_admin_timeline_stream_accounts
    remove_instance_variable(:@admin_timeline_stream_account_ids) if defined?(@admin_timeline_stream_account_ids)
  end
end
