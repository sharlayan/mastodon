# frozen_string_literal: true

class MisskeyCompat::ChannelRenoteService < ReblogService
  def call(account, reblogged_status, channel)
    reblogged_status = reblogged_status.reblog if reblogged_status.reblog?

    authorize_with account, reblogged_status, :reblog?

    reblog = account.statuses.find_by(reblog: reblogged_status)
    return reblog unless reblog.nil?

    reblog = ApplicationRecord.transaction do
      account.statuses.create!(reblog: reblogged_status, text: '', visibility: :public, local_only: true).tap do |status|
        MisskeyChannelNote.create!(status: status, misskey_channel: channel)
      end
    end

    Trends.register!(reblog)
    DistributionWorker.perform_async(reblog.id)
    create_notification(reblog)
    increment_statistics

    reblog
  end
end
