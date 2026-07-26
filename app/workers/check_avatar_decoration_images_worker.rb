# frozen_string_literal: true

class CheckAvatarDecorationImagesWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 0

  BATCH_SIZE = 100

  def perform(account_id = nil)
    scope = account_id.nil? ? repairable_scope : account_scope(account_id)
    return if scope.nil?

    scope.in_batches(of: BATCH_SIZE) do |batch|
      batch.pluck(:id).each { |id| RedownloadAvatarDecorationWorker.enqueue(id, account_id: account_id) }
    end
  end

  private

  def repairable_scope
    AvatarDecoration.where.not(image_remote_url: [nil, ''])
  end

  def account_scope(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil?

    decoration_ids = account.avatar_decorations.filter_map { |config| config['id'] }
    return if decoration_ids.empty?

    repairable_scope.where(id: decoration_ids)
  end
end
