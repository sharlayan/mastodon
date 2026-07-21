# frozen_string_literal: true

class MisskeyAccessGrant < ApplicationRecord
  belongs_to :access_token, class_name: 'Doorkeeper::AccessToken', inverse_of: :misskey_access_grant

  validates :access_token_id, uniqueness: true
  validate :permissions_are_supported

  def allows?(permission)
    permission.present? && permissions.include?(permission)
  end

  private

  def permissions_are_supported
    invalid = permissions - MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS
    errors.add(:permissions, :invalid) if invalid.any?
  end
end
