# frozen_string_literal: true

class Sharlayan::FollowMessageService < BaseService
  MAX_LENGTH = 256

  def call(follow, message, recipient:)
    store(follow, message)
    notify(follow, recipient:) if follow.follow_message.present?
    follow
  end

  def store(follow, message)
    return follow if message.blank?

    follow.update_column(:follow_message, message.truncate(MAX_LENGTH))
    follow
  end

  def notify(follow, recipient:)
    LocalNotificationWorker.perform_async(recipient.id, follow.id, 'Follow', 'follow_accepted') if recipient.local? && follow.follow_message.present?
  end

  def call_for_request(request, message)
    return if message.blank? || !request.account.local?

    follow = Follow.find_by(account: request.account, target_account: request.target_account)
    call(follow, message, recipient: request.account) if follow
  end
end
