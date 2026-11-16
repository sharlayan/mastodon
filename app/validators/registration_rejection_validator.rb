# frozen_string_literal: true

class RegistrationRejectionValidator < ActiveModel::Validator
  def validate(user)
    return if user.bypass_registration_checks?
    return unless Sharlayan::RegistrationRejectionPatterns.match?(user.email, Setting.registration_reject_email_pattern) || Sharlayan::RegistrationRejectionPatterns.match?(user.account&.username, Setting.registration_reject_username_pattern)

    user.errors.add(:base, I18n.t('auth.registration_rejected'))
  end
end
