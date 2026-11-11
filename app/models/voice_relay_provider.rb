# frozen_string_literal: true

# == Schema Information
#
# Table name: voice_relay_providers
#
#  id                 :bigint(8)        not null, primary key
#  capacity           :jsonb            not null
#  credential_version :string           not null
#  enabled            :boolean          default(TRUE), not null
#  events_cursor      :string
#  last_checked_at    :datetime
#  last_error         :string
#  origin             :string           not null
#  revoked_at         :datetime
#  secret_ciphertext  :text             not null
#  validated          :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class VoiceRelayProvider < ApplicationRecord
  MAX_PROVIDERS = 8
  SECRET_MIN_LENGTH = Sharlayan::VoiceRelay::Client::SECRET_MIN_LENGTH
  SECRET_MAX_LENGTH = 1024

  attr_reader :secret_input

  has_many :voice_call_allocations, dependent: nil

  scope :usable, -> { where(enabled: true, validated: true) }

  before_validation :normalize_origin
  before_validation :reset_validation, if: -> { new_record? || origin_changed? || secret_ciphertext_changed? }

  validates :origin, presence: true, uniqueness: true
  validate :validate_origin
  validate :validate_secret_presence
  validate :validate_secret_input
  validate :validate_provider_limit, on: :create
  validate :validate_origin_unchanged_during_calls, on: :update

  before_destroy :ensure_no_unfinished_calls

  def secret=(value)
    @secret_input = value.to_s.strip
    return if @secret_input.empty?

    self.secret_ciphertext = Sharlayan::VoiceRelay::SecretBox.encrypt(@secret_input)
  end

  def secret
    return if secret_ciphertext.blank?

    Sharlayan::VoiceRelay::SecretBox.decrypt(secret_ciphertext)
  end

  def client
    Sharlayan::VoiceRelay::Client.new(self)
  end

  def check!
    version = credential_version
    capacity = client.capacity

    record_check(version, validated: capacity['enabled'], capacity:, last_error: nil, revoked_at: nil)
    capacity
  rescue Sharlayan::VoiceRelay::Error => e
    record_check(version, **self.class.error_attributes(e, revoked_at:))
    raise
  end

  def self.error_attributes(error, revoked_at: nil)
    return { last_error: error.code.to_s.first(64) } unless error.revoked?

    { last_error: error.code.to_s.first(64), validated: false, revoked_at: revoked_at || Time.now.utc }
  end

  def revoked?
    revoked_at.present?
  end

  def to_log_human_identifier
    origin
  end

  private

  def record_check(version, **attributes)
    self.class.where(id:, credential_version: version).update_all(attributes.merge(last_checked_at: Time.now.utc, updated_at: Time.now.utc))
    reload
  end

  def normalize_origin
    self.origin = Sharlayan::VoiceRelay::Origin.normalize(origin)
  rescue Sharlayan::VoiceRelay::Error
    nil
  end

  def reset_validation
    self.credential_version = SecureRandom.uuid
    self.validated = false
    self.capacity = {}
    self.last_error = nil
    self.last_checked_at = nil
    self.revoked_at = nil
  end

  def validate_origin
    return if origin.blank?

    normalized = Sharlayan::VoiceRelay::Origin.normalize(origin)
    errors.add(:origin, :own_origin) if Sharlayan::VoiceRelay::Origin.local?(normalized)
  rescue Sharlayan::VoiceRelay::Error
    errors.add(:origin, :invalid)
  end

  def validate_secret_presence
    errors.add(:secret, :blank) if secret_ciphertext.blank?
  end

  def validate_secret_input
    return if secret_input.blank?

    errors.add(:secret, :too_short, count: SECRET_MIN_LENGTH) if secret_input.length < SECRET_MIN_LENGTH
    errors.add(:secret, :too_long, count: SECRET_MAX_LENGTH) if secret_input.length > SECRET_MAX_LENGTH
  end

  def ensure_no_unfinished_calls
    return unless voice_call_allocations.unfinished.exists?

    errors.add(:base, :unfinished_calls)
    throw :abort
  end

  def validate_origin_unchanged_during_calls
    errors.add(:origin, :unfinished_calls) if origin_changed? && voice_call_allocations.unfinished.exists?
  end

  def validate_provider_limit
    errors.add(:base, :provider_limit, count: MAX_PROVIDERS) if self.class.count >= MAX_PROVIDERS
  end
end
