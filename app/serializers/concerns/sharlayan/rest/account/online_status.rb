# frozen_string_literal: true

module Sharlayan::REST::Account::OnlineStatus
  extend ActiveSupport::Concern

  included do
    attribute :online_status
  end

  def online_status
    return 'unknown' unless Setting.online_status_enabled
    return 'unknown' if current_user.nil? || object.unavailable? || object.user.nil?

    object.user.online_status
  end
end
