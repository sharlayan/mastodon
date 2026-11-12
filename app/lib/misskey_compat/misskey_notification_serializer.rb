# frozen_string_literal: true

module MisskeyCompat
  module MisskeyNotificationSerializer
    module_function

    def serialize(notification, user: nil)
      from_account = notification.from_account
      data = {
        id: MisskeyCompat::MiId.encode(notification.id),
        createdAt: notification.created_at.iso8601,
        type: notification.notification_type,
      }

      if from_account
        data[:userId] = MisskeyCompat::MiId.encode(from_account.id)
        data[:user] = user || MisskeyCompat::UserSerializer.serialize(from_account)
      end

      data.merge(notification.data.symbolize_keys.except(*data.keys))
    end
  end
end
