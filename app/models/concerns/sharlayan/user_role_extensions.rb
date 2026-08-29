# frozen_string_literal: true

module Sharlayan::UserRoleExtensions
  extend ActiveSupport::Concern
  include Redisable

  RATE_LIMITS = {
    api: { attribute: :api_rate_limit, default: 1_500 },
    api_token: { attribute: :api_token_rate_limit, default: 1_500 },
    api_paging: { attribute: :api_paging_rate_limit, default: 1_000 },
    api_media: { attribute: :api_media_rate_limit, default: 100 },
    api_delete: { attribute: :api_delete_rate_limit, default: 60 },
    drive_upload: { attribute: :drive_upload_rate_limit, default: 100 },
  }.freeze

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
    RATE_LIMITS.each_value do |config|
      validates config[:attribute], numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    end

    validate :validate_extra_permissions_elevation
    validate :validate_sharlayan_own_role_edition
    validate :validate_rate_limit_management
    validate :validate_rate_limit_hierarchy

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

  def rate_limit_for(name)
    config = RATE_LIMITS.fetch(name)
    self[config[:attribute]] || config[:default]
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
    return unless defined?(@current_account)

    permitted = @current_account.user_role.computed_extra_permissions
    permitted |= EXTRA_FLAGS[:bypass_rate_limit] if current_account_rate_limit_manager?
    errors.add(:extra_permissions_as_keys, :elevated) if permitted & extra_permissions != extra_permissions
  end

  def validate_rate_limit_management
    return unless defined?(@current_account) && !current_account_rate_limit_manager?

    errors.add(:extra_permissions_as_keys, :restricted) if bypass_rate_limit_permission_changed?
    RATE_LIMITS.each_value do |config|
      errors.add(config[:attribute], :restricted) if will_save_change_to_attribute?(config[:attribute])
    end
  end

  def validate_rate_limit_hierarchy
    return if position.blank? || rate_limit_bypassed_role?

    roles = self.class.where.not(id: id).reject { |role| rate_limit_bypassed_role?(role) }

    RATE_LIMITS.each do |name, config|
      value = self[config[:attribute]] || config[:default]
      lower_maximum = roles.select { |role| role.position < position }.filter_map { |role| role.rate_limit_for(name) }.max
      upper_minimum = roles.select { |role| role.position > position }.filter_map { |role| role.rate_limit_for(name) }.min

      errors.add(config[:attribute], :lower_than_subordinate) if lower_maximum && value < lower_maximum
      errors.add(config[:attribute], :higher_than_superior) if upper_minimum && value > upper_minimum
    end
  end

  def bypass_rate_limit_permission_changed?
    return false unless will_save_change_to_extra_permissions?

    previous, current = extra_permissions_change_to_be_saved
    flag = EXTRA_FLAGS[:bypass_rate_limit]
    (previous & flag) != (current & flag)
  end

  def current_account_rate_limit_manager?
    role = @current_account.user_role
    role.administrator? || (!role.everyone? && role.position == self.class.assignable.maximum(:position))
  end

  def rate_limit_bypassed_role?(role = self)
    flag = EXTRA_FLAGS[:bypass_rate_limit]
    everyone_permissions = everyone? ? extra_permissions : self.class.where(id: self.class::EVERYONE_ROLE_ID).pick(:extra_permissions).to_i

    role.administrator? || role.extra_permissions.anybits?(flag) || everyone_permissions.anybits?(flag)
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
