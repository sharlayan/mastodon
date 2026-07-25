# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_access_grants
#
#  id              :bigint(8)        not null, primary key
#  permissions     :string           default([]), not null, is an Array
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  access_token_id :bigint(8)        not null
#
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
