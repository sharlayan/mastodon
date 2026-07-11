# frozen_string_literal: true

module User::Activity
  extend ActiveSupport::Concern

  # The home and list feeds will be stored for this amount of time, and status
  # fan-out to followers will include only people active within this time frame.
  #
  # Lowering the duration may improve performance if many people sign up, but
  # most will not check their feed every day. Raising the duration reduces the
  # amount of background processing that happens when people become active.
  ACTIVE_DURATION = ENV.fetch('USER_ACTIVE_DAYS', 7).to_i.days

  ONLINE_STATUS_THRESHOLD = 10.minutes
  ACTIVE_STATUS_THRESHOLD = 3.days
  LAST_ACTIVE_THROTTLE = 5.minutes

  included do
    scope :signed_in_recently, -> { where(current_sign_in_at: ACTIVE_DURATION.ago..) }
    scope :not_signed_in_recently, -> { where(current_sign_in_at: ...ACTIVE_DURATION.ago) }
  end

  def signed_in_recently?
    current_sign_in_at.present? && current_sign_in_at >= ACTIVE_DURATION.ago
  end

  def update_last_active!
    return if last_active_at.present? && last_active_at > LAST_ACTIVE_THROTTLE.ago

    update_column(:last_active_at, Time.now.utc)
  end

  def online_status
    return 'unknown' if settings['hide_online_status']
    return 'unknown' if last_active_at.nil?

    elapsed = Time.now.utc - last_active_at

    if elapsed < ONLINE_STATUS_THRESHOLD
      'online'
    elsif elapsed < ACTIVE_STATUS_THRESHOLD
      'active'
    else
      'offline'
    end
  end

  private

  def inactive_since_duration?
    last_sign_in_at < ACTIVE_DURATION.ago
  end
end
