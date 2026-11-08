# frozen_string_literal: true

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
