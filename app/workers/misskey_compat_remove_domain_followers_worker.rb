# frozen_string_literal: true

class MisskeyCompatRemoveDomainFollowersWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: false, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform(domain)
    follows = Follow.joins(:account).where(accounts: { domain: domain }).where(target_account_id: Account.local.select(:id))

    follows.distinct.pluck(:target_account_id).each_slice(100) do |target_ids|
      Account.where(id: target_ids).find_each do |target_account|
        follower_ids = follows.where(target_account_id: target_account.id).pluck(:account_id)
        RemoveFromFollowersService.new.call(target_account, follower_ids)
      end
    end
  end
end
