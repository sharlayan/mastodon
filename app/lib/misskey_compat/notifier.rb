# frozen_string_literal: true

class MisskeyCompat::Notifier
  include Redisable

  def self.notify!(account, type, from_account: nil, **data)
    new.notify!(account, type, data, from_account: from_account)
  end

  def notify!(account, type, data, from_account: nil)
    return if account.nil? || !account.local?
    return if from_account && (from_account.id == account.id || account.muting?(from_account) || account.blocking?(from_account))

    notification = MisskeyNotification.create!(account: account, from_account: from_account, notification_type: type, data: data.deep_stringify_keys)
    MisskeyNotification.trim!(account)
    broadcast(notification)
    notification
  end

  private

  def broadcast(notification)
    MisskeyCompat::Streaming.broadcast_main(redis, notification.account, 'notification') do
      MisskeyCompat::MisskeyNotificationSerializer.serialize(notification)
    end
  end
end
