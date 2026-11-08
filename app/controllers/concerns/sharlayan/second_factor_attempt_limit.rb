# frozen_string_literal: true

module Sharlayan::SecondFactorAttemptLimit
  extend ActiveSupport::Concern

  include Redisable

  private

  def second_factor_attempts_exceeded?(user)
    key = second_factor_attempts_key(user)
    attempts, = redis.multi do |multi|
      multi.incr(key)
      multi.expire(key, 1.hour)
    end

    attempts >= Auth::SessionsController::MAX_2FA_ATTEMPTS_PER_HOUR
  end

  def clear_second_factor_attempts(user)
    redis.del(second_factor_attempts_key(user))
  end

  def notify_failed_second_factor(user)
    UserMailer.failed_2fa(user, request.remote_ip, request.user_agent, Time.now.utc).deliver_later!
  end

  def second_factor_attempts_key(user)
    "2fa_auth_attempts:#{user.id}:#{Time.now.utc.hour}"
  end
end
