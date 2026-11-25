# frozen_string_literal: true

module Sharlayan::ReactionQuietHours
  TIMES = (0...48).map { |slot| format('%<hour>02d:%<minute>02d', hour: slot / 2, minute: (slot % 2) * 30) }.freeze

  module_function

  def blocks?(status_account, reacting_account, at = Time.current)
    return false if status_account.nil? || reacting_account.nil?
    return false unless status_account.local?
    return false if status_account.id == reacting_account.id

    active?(status_account.user, at)
  end

  def active?(user, at = Time.current)
    return false if user.nil? || !user.settings['reaction_quiet_hours']

    start_minutes = minutes_of(user.settings['reaction_quiet_hours_start'])
    end_minutes = minutes_of(user.settings['reaction_quiet_hours_end'])
    return false if start_minutes.nil? || end_minutes.nil?

    local = at.in_time_zone(time_zone_for(user))
    now = (local.hour * 60) + local.min

    if start_minutes == end_minutes
      true
    elsif start_minutes < end_minutes
      now >= start_minutes && now < end_minutes
    else
      now >= start_minutes || now < end_minutes
    end
  end

  def time_zone_for(user)
    ActiveSupport::TimeZone[user.time_zone.to_s] || Time.zone
  end

  def minutes_of(value)
    return unless TIMES.include?(value)

    hour, minute = value.split(':').map(&:to_i)
    (hour * 60) + minute
  end
end
