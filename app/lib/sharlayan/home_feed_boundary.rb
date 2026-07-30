# frozen_string_literal: true

class Sharlayan::HomeFeedBoundary
  def self.resolve(account, status_id)
    new(account, status_id).resolve
  end

  def initialize(account, status_id)
    @account   = account
    @status_id = status_id.to_i
  end

  def resolve
    return nil unless @status_id.positive?

    database_boundary
  end

  private

  def database_boundary
    reblogs = Status.where(reblog_of_id: @status_id)

    reblogs
      .where(account_id: @account.following.select(:id))
      .or(reblogs.where(account_id: @account.id))
      .minimum(:id)
  end
end
