# frozen_string_literal: true

# Fetches the attachments of a message from another server and redraws the message on open screens as each one
# arrives. One job per message keeps the redraws in order, so a slower attachment cannot overwrite a newer view
# of the message, and an attachment that cannot be fetched yet does not hold back the others.
class ChatMediaDownloadWorker
  include Sidekiq::Worker
  include ExponentialBackoff

  sidekiq_options queue: 'pull', retry: 3

  def perform(message_id)
    message = showable_message(message_id)
    return if message.nil?

    pending = message.media_attachments.select(&:needs_redownload?).map(&:id)
    failure = nil

    pending.each do |media_id|
      RedownloadMediaWorker.new.perform(media_id) if showable_message(message_id)
      announce(message_id)
    rescue => e
      failure ||= e
    end

    # A viewer's request through the media proxy may have fetched everything before this job ran.
    announce(message_id) if pending.empty?
    raise failure if failure
  end

  private

  def announce(message_id)
    message = showable_message(message_id)
    Sharlayan::ChatService.new.announce_downloaded_media(message) if message
  end

  def showable_message(message_id)
    message = ChatMessage.find_by(id: message_id)
    message unless message.nil? || message.deleted? || message.account.suspended?
  end
end
