# frozen_string_literal: true

module Sharlayan::LocalContentAccess
  module_function

  def accessible?(mode, user)
    mode == 'public' || (user.present? && (mode != 'disabled' || user.can?(:view_feeds)))
  end

  def account_statuses_accessible?(account, user)
    !account.local? || accessible?(Setting.local_account_statuses_access, user)
  end
end
