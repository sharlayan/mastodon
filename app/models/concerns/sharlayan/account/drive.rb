# frozen_string_literal: true

module Sharlayan::Account::Drive
  def drive_quota_bytes
    (user&.role || UserRole.everyone).drive_quota_bytes
  end
end
