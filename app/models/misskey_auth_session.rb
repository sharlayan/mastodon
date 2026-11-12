# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_auth_sessions
#
#  id                   :bigint(8)        not null, primary key
#  token                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  oauth_application_id :bigint(8)        not null
#  user_id              :bigint(8)
#
class MisskeyAuthSession < ApplicationRecord
  TTL = 15.minutes

  belongs_to :application, class_name: 'Doorkeeper::Application', foreign_key: :oauth_application_id, inverse_of: false
  belongs_to :user, optional: true

  scope :active, -> { where(created_at: TTL.ago..) }
  scope :expired, -> { where(created_at: ...TTL.ago) }

  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  private

  def generate_token
    self.token ||= SecureRandom.uuid
  end
end
