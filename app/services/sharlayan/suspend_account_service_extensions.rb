# frozen_string_literal: true

module Sharlayan::SuspendAccountServiceExtensions
  def call(account)
    super

    Sharlayan::ChatService.new.remove_suspended_account(account) if account.suspended?
  end
end
