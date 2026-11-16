# frozen_string_literal: true

module Sharlayan::Account::Profile
  extend ActiveSupport::Concern

  BIRTHDAY_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

  included do
    validates :followed_message, length: { maximum: 256 }, if: -> { local? && will_save_change_to_followed_message? }
    validate :validate_birthday, if: -> { local? && will_save_change_to_birthday? }
    normalizes :birthday, with: ->(value) { value.to_s.strip.presence }
  end

  def birthday_visible_to?(viewer)
    return false if birthday.blank? || unavailable?
    return true if viewer && viewer.id == id
    return true unless local?

    user&.settings&.[]('show_birthday') == true
  end

  def featureable?
    local? && discoverable?
  end

  def sharlayan_emojifiable_text
    followed_message
  end

  private

  def validate_birthday
    return if birthday.nil?

    year, month, day = birthday.match?(BIRTHDAY_FORMAT) ? birthday.split('-').map(&:to_i) : []
    errors.add(:birthday, :invalid) unless year && year >= 1900 && Date.valid_date?(year, month, day) && Date.new(year, month, day) <= Time.zone.today
  end
end
